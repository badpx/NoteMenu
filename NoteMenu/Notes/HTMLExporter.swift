import AppKit

/// 把编辑区内容转成备忘录接受的白名单 HTML（h1/h2/b/i/u/strike/tt/pre/ul/ol/li/div），
/// 首行作为备忘录标题。块级分类（列表/标题/代码块）以 EditorDocument 模型为真值（§11），
/// 行内格式（粗/斜/下划线/删除线/行内代码）读 storage 字体与样式属性。
enum HTMLExporter {
    static let bodyFontSize: CGFloat = 14
    static let h1FontSize: CGFloat = 24
    static let h2FontSize: CGFloat = 18
    static let codeFontSize: CGFloat = 12
    static let codeFontName = "Courier"

    /// 行内代码/代码块用 Courier 12px 承载：CJK 字符会被字体替换吃掉 Courier 族名，
    /// 但字号 12 在替换与 RTFD 草稿往返后都保留，因此判定同时看族名与字号。
    static func isCodeFont(_ font: NSFont) -> Bool {
        font.familyName == codeFontName || font.pointSize == codeFontSize
    }

    static var codeFont: NSFont {
        NSFont(name: codeFontName, size: codeFontSize) ?? NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
    }

    struct Result {
        let title: String
        let bodyHTML: String
    }

    static func export(_ attributedString: NSAttributedString, document: EditorDocument) -> Result {
        document.syncFromStorage(
            (attributedString as? NSTextStorage) ?? NSTextStorage(string: attributedString.string)
        )

        var paragraphIndices: [Int] = Array(0..<document.paragraphCount)
        // 末尾零长度空段落不导出（与既有行为一致）
        if let last = paragraphIndices.last, document.paragraphRange(at: last).length == 0 {
            paragraphIndices.removeLast()
        }
        if paragraphIndices.isEmpty {
            paragraphIndices = [0]
        }

        let title = plainText(of: document.paragraphRange(at: paragraphIndices[0]), in: attributedString)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? "未命名笔记" : title

        var body = "<h1>\(escape(resolvedTitle))</h1>"
        /// 列表栈：index 即嵌套层级（0 为最外层），值是该层标签 ul/ol。
        var listStack: [String] = []
        /// 上一个段落的顶层列表类型（用于异类顶层列表相邻时强制空行，备忘录会并轨丢编号）。
        var previousTopListTag: String?
        var inPre = false

        for index in paragraphIndices.dropFirst() {
            let format = document.format(at: index)
            let paragraphRange = document.paragraphRange(at: index)
            let tags: [String] = format.isList
                ? (0..<format.listLevel).map { _ in format.ordered ? "ol" : "ul" }
                : []
            let headingLevel: Int = switch format.kind {
            case .h1: 1
            case .h2: 2
            default: 0
            }

            // 代码块：连续代码块段落合并为一个 <pre>（备忘录探针实测支持）。
            if format.kind == .codeBlock, tags.isEmpty {
                while let tag = listStack.popLast() { body += "</\(tag)>" }
                if !inPre { body += "<pre>"; inPre = true }
                let line = plainText(of: paragraphRange, in: attributedString)
                    .replacingOccurrences(of: "\u{2028}", with: "\n")
                body += escape(line) + "\n"
                previousTopListTag = nil
                continue
            }
            if inPre { body += "</pre>"; inPre = false }

            if tags.isEmpty {
                while let tag = listStack.popLast() { body += "</\(tag)>" }
            } else {
                // 回到浅层：关闭更深层级
                while listStack.count > tags.count {
                    body += "</\(listStack.removeLast())>"
                }
                // 同层异类：关闭重开
                if listStack.count == tags.count, listStack.last != tags.last {
                    body += "</\(listStack.removeLast())>"
                }
                // 深入新层级
                if listStack.count < tags.count {
                    // 顶层异类列表直接相邻（中间无空行）会被备忘录并轨，强制空行分隔
                    if listStack.isEmpty, let previous = previousTopListTag, previous != tags[0] {
                        body += "<div><br></div>"
                    }
                    while listStack.count < tags.count {
                        let tag = tags[listStack.count]
                        body += "<\(tag)>"
                        listStack.append(tag)
                    }
                }
            }

            if !tags.isEmpty {
                let content = renderRuns(of: paragraphRange, in: attributedString)
                body += content.isEmpty ? "<li><br></li>" : "<li>\(content)</li>"
            } else if headingLevel > 0 {
                let content = renderRuns(of: paragraphRange, in: attributedString, skipBold: true)
                body += content.isEmpty
                    ? "<h\(headingLevel)><br></h\(headingLevel)>"
                    : "<h\(headingLevel)>\(content)</h\(headingLevel)>"
            } else {
                let content = renderRuns(of: paragraphRange, in: attributedString)
                body += content.isEmpty ? "<div><br></div>" : "<div>\(content)</div>"
            }
            previousTopListTag = tags.first
        }
        while let tag = listStack.popLast() { body += "</\(tag)>" }
        if inPre { body += "</pre>" }

        return Result(title: resolvedTitle, bodyHTML: body)
    }

    /// 段落去掉末尾换行后的纯文本（附件占位符剔除）。
    private static func plainText(of paragraphRange: NSRange, in attributedString: NSAttributedString) -> String {
        let contentRange = EditorDocument.contentRange(
            of: paragraphRange,
            in: attributedString.string as NSString
        )
        guard contentRange.length > 0 else { return "" }
        return (attributedString.string as NSString)
            .substring(with: contentRange)
            .replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    private static func renderRuns(
        of paragraphRange: NSRange,
        in attributedString: NSAttributedString,
        skipBold: Bool = false
    ) -> String {
        let string = attributedString.string as NSString
        let contentRange = EditorDocument.contentRange(of: paragraphRange, in: string)
        guard contentRange.length > 0 else { return "" }

        var html = ""
        attributedString.enumerateAttributes(in: contentRange) { attributes, subrange, _ in
            var text = string.substring(with: subrange)
                .replacingOccurrences(of: "\u{FFFC}", with: "")
            guard !text.isEmpty else { return }
            text = escape(text).replacingOccurrences(of: "\u{2028}", with: "<br>")

            let font = attributes[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let isBold = traits.contains(.boldFontMask)
            // 斜体可能是字体 italic trait，也可能是合成倾斜（中文等 CJK 字体无斜体变体）。
            let obliqueness = (attributes[.obliqueness] as? NSNumber)?.floatValue ?? 0
            let isItalic = traits.contains(.italicFontMask) || obliqueness > 0
            let isUnderlined = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
            let isStrikethrough = ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0
            let isCode = font.map { isCodeFont($0) } ?? false

            if isCode { text = "<tt>\(text)</tt>" }
            if isStrikethrough { text = "<strike>\(text)</strike>" }
            if isUnderlined { text = "<u>\(text)</u>" }
            if isItalic { text = "<i>\(text)</i>" }
            if isBold, !skipBold { text = "<b>\(text)</b>" }
            html += text
        }
        return html
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
