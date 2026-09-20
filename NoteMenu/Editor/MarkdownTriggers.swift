import Foundation

/// Markdown 标志触发识别：纯函数（EditorSpec §3.1）。
/// 调用方负责前置条件（IME 组合中不调用、块级触发要求段落为正文等）。
enum MarkdownTriggers {
    // MARK: - 块级

    enum BlockAction: Equatable {
        case heading(Int)
        case unorderedList
        case orderedList
        case codeBlock
    }

    /// 输入空格后判定：prefix 为「段落起点到光标」的文本（含刚输入的空格）。
    /// 命中即应转换；调用方负责删除标记字符。
    static func blockAction(paragraphPrefix prefix: String) -> BlockAction? {
        switch prefix {
        case "# ": return .heading(1)
        case "## ": return .heading(2)
        case "### ": return .heading(3)
        case "- ", "* ": return .unorderedList
        case "``` ": return .codeBlock
        default:
            // 有序列表：1~2 位数字 + ". "
            if prefix.hasSuffix(". ") {
                let digits = prefix.dropLast(2)
                if !digits.isEmpty, digits.count <= 2, digits.allSatisfy(\.isNumber) {
                    return .orderedList
                }
            }
            return nil
        }
    }

    // MARK: - 行内配对

    enum InlineFormat: Equatable {
        case bold, italic, strikethrough, code
    }

    struct InlineMatch: Equatable {
        let format: InlineFormat
        /// 标记长度（1 或 2）
        let markerLength: Int
        /// 内容区间（行内坐标）
        let contentRange: NSRange
        /// 开口标记区间（行内坐标）
        let openMarkerRange: NSRange
        /// 闭合标记区间（行内坐标）
        let closeMarkerRange: NSRange
    }

    /// 开口符前的合法边界字符：空白 / 标点（含 CJK 标点，CharacterSet.punctuationCharacters 不含全角括号等）。
    private static let boundaryCharacters: CharacterSet = {
        var set = CharacterSet.whitespaces.union(.punctuationCharacters)
        set.formUnion(CharacterSet(charactersIn: "（）【】「」『』《》〈〉、。，．；：？！…—·～"))
        return set
    }()

    /// 输入闭合符后判定：lineText 为「行起点到光标」的文本（含刚输入的闭合符）。
    /// 命中条件（§3.1）：开口符前是行首/空白/标点；内容首尾非空白、内部不含同标记符；
    /// 单字符标记不匹配双字符标记的半边。
    static func inlineMatch(lineText: String) -> InlineMatch? {
        let line = lineText as NSString
        guard line.length > 0 else { return nil }
        let typed = line.substring(from: line.length - 1)

        // 顺序敏感：先双字符标记后单字符标记
        let candidates: [(marker: String, format: InlineFormat)] = [
            ("**", .bold), ("~~", .strikethrough), ("__", .bold),
            ("`", .code), ("*", .italic), ("_", .italic),
        ]
        for (marker, format) in candidates {
            guard marker.hasSuffix(typed) else { continue }
            let markerLength = (marker as NSString).length
            guard line.length >= markerLength * 2 + 1,
                  line.hasSuffix(marker) else { continue }
            let searchLength = line.length - markerLength
            let openLocation = line.range(
                of: marker,
                options: .backwards,
                range: NSRange(location: 0, length: searchLength)
            ).location
            guard openLocation != NSNotFound else { continue }

            // 开口符前必须是行首/空白/标点（防止 snake_case、2*3 这类误触发）
            if openLocation > 0 {
                let before = line.character(at: openLocation - 1)
                guard let scalar = Unicode.Scalar(before),
                      Self.boundaryCharacters.contains(scalar) else {
                    continue
                }
            }
            // 单字符标记不匹配双字符标记的半边
            if markerLength == 1 {
                let markerChar = (marker as NSString).character(at: 0)
                if openLocation > 0, line.character(at: openLocation - 1) == markerChar { continue }
                if openLocation + 1 < line.length, line.character(at: openLocation + 1) == markerChar { continue }
            }

            let contentRange = NSRange(
                location: openLocation + markerLength,
                length: searchLength - openLocation - markerLength
            )
            guard contentRange.length > 0 else { continue }
            let content = line.substring(with: contentRange)
            // 内容首尾非空白、内部不含同标记符
            if content.hasPrefix(" ") || content.hasSuffix(" ") { continue }
            if content.rangeOfCharacter(from: CharacterSet(charactersIn: marker)) != nil { continue }

            return InlineMatch(
                format: format,
                markerLength: markerLength,
                contentRange: contentRange,
                openMarkerRange: NSRange(location: openLocation, length: markerLength),
                closeMarkerRange: NSRange(location: line.length - markerLength, length: markerLength)
            )
        }
        return nil
    }
}
