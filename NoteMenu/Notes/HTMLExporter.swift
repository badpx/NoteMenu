import AppKit

/// 把编辑区的 NSAttributedString 转成备忘录接受的白名单 HTML（h1/b/i/u/ul/ol/li/div），
/// 首行作为备忘录标题。
enum HTMLExporter {
    struct Result {
        let title: String
        let bodyHTML: String
    }

    static func export(_ attributedString: NSAttributedString) -> Result {
        let string = attributedString.string as NSString
        var paragraphs: [(range: NSRange, marker: NSTextList.MarkerFormat?)] = []

        var location = 0
        while location < string.length {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            let style = attributedString.attribute(
                .paragraphStyle,
                at: paragraphRange.location,
                effectiveRange: nil
            ) as? NSParagraphStyle
            paragraphs.append((paragraphRange, style?.textLists.first?.markerFormat))
            location = NSMaxRange(paragraphRange)
        }
        if paragraphs.isEmpty {
            paragraphs.append((NSRange(location: 0, length: 0), nil))
        }

        let title = plainText(of: paragraphs[0].range, in: attributedString)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? "未命名笔记" : title

        var body = "<h1>\(escape(resolvedTitle))</h1>"
        var openListTag: String?
        for paragraph in paragraphs.dropFirst() {
            let listTag: String? = switch paragraph.marker {
            case .decimal: "ol"
            case .some: "ul"
            case nil: nil
            }
            if listTag != openListTag {
                if let openListTag { body += "</\(openListTag)>" }
                if let listTag { body += "<\(listTag)>" }
                openListTag = listTag
            }
            let content = renderRuns(of: paragraph.range, in: attributedString)
            if listTag != nil {
                body += content.isEmpty ? "<li><br></li>" : "<li>\(content)</li>"
            } else {
                body += content.isEmpty ? "<div><br></div>" : "<div>\(content)</div>"
            }
        }
        if let openListTag { body += "</\(openListTag)>" }

        return Result(title: resolvedTitle, bodyHTML: body)
    }

    /// 段落去掉末尾换行后的纯文本（附件占位符剔除）。
    private static func plainText(of paragraphRange: NSRange, in attributedString: NSAttributedString) -> String {
        let contentRange = contentRangeOfParagraph(paragraphRange, in: attributedString.string as NSString)
        guard contentRange.length > 0 else { return "" }
        return (attributedString.string as NSString)
            .substring(with: contentRange)
            .replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    private static func contentRangeOfParagraph(_ paragraphRange: NSRange, in string: NSString) -> NSRange {
        var length = paragraphRange.length
        while length > 0 {
            let last = string.character(at: paragraphRange.location + length - 1)
            guard let scalar = Unicode.Scalar(last), CharacterSet.newlines.contains(scalar) else { break }
            length -= 1
        }
        return NSRange(location: paragraphRange.location, length: length)
    }

    private static func renderRuns(of paragraphRange: NSRange, in attributedString: NSAttributedString) -> String {
        let string = attributedString.string as NSString
        let contentRange = contentRangeOfParagraph(paragraphRange, in: string)
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

            if isUnderlined { text = "<u>\(text)</u>" }
            if isItalic { text = "<i>\(text)</i>" }
            if isBold { text = "<b>\(text)</b>" }
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
