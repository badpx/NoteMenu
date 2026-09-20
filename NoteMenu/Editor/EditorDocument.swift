import AppKit

/// 段落格式：编辑器的格式单一真值（EditorSpec §5.4 / §11）。
/// 空段落（无任何字符、文档末尾）也持有格式；不依赖 typingAttributes。
struct ParagraphFormat: Equatable {
    enum Kind: Equatable {
        case body
        case h1
        case h2
        case h3
        case codeBlock
        case listItem
    }

    var kind: Kind = .body
    /// listItem 专用：1...ListLayout.maxLevel
    var listLevel: Int = 0
    /// listItem 专用：true = 有序（ol）
    var ordered: Bool = false

    static let body = ParagraphFormat()

    var isList: Bool { kind == .listItem && listLevel > 0 }
}

/// 段落模型：格式数组按段落下标与 textStorage 对齐。
/// 段落区间从文本推导（含末尾无字符的空段落），结构变更由 EditorCore 显式维护，
/// syncFromStorage 仅作安全兜底（对齐数量）。
final class EditorDocument {
    private(set) var formats: [ParagraphFormat] = []
    private(set) var ranges: [NSRange] = []

    var paragraphCount: Int { ranges.count }

    // MARK: - 区间推导

    /// 段落区间推导：末尾字符是换行符（或整篇为空）时补出末尾空段落 {length, 0}。
    static func paragraphRanges(of string: String) -> [NSRange] {
        let ns = string as NSString
        var ranges: [NSRange] = []
        var location = 0
        while location < ns.length {
            let range = ns.paragraphRange(for: NSRange(location: location, length: 0))
            ranges.append(range)
            location = NSMaxRange(range)
        }
        if ns.length == 0 || (ns.length > 0 && CharacterSet.newlines.contains(Unicode.Scalar(ns.character(at: ns.length - 1))!)) {
            ranges.append(NSRange(location: ns.length, length: 0))
        }
        return ranges
    }

    // MARK: - 读写

    func format(at index: Int) -> ParagraphFormat {
        guard formats.indices.contains(index) else { return .body }
        return formats[index]
    }

    func setFormat(_ format: ParagraphFormat, atParagraph index: Int) {
        guard formats.indices.contains(index) else { return }
        formats[index] = format
    }

    func insertFormat(_ format: ParagraphFormat, atParagraph index: Int) {
        formats.insert(format, at: min(index, formats.count))
    }

    func removeFormat(atParagraph index: Int) {
        guard formats.indices.contains(index), formats.count > 1 else { return }
        formats.remove(at: index)
    }

    /// undo/redo 还原：整体替换格式数组（区间随后由 syncFromStorage 重算对齐）。
    func restoreFormats(_ restored: [ParagraphFormat]) {
        formats = restored
    }

    func paragraphIndex(atLocation location: Int) -> Int {
        for (index, range) in ranges.enumerated() {
            if location >= range.location && location < NSMaxRange(range) { return index }
            // 零长度段落（末尾空段落）
            if range.length == 0 && location == range.location { return index }
        }
        return max(0, ranges.count - 1)
    }

    func paragraphRange(at index: Int) -> NSRange {
        guard ranges.indices.contains(index) else { return NSRange(location: 0, length: 0) }
        return ranges[index]
    }

    // MARK: - 同步

    /// 结构安全网：区间从文本重算，格式数组按数量对齐（多余截断、不足补正文）。
    /// 结构性变更（Enter/Backspace/粘贴）由 EditorCore 显式维护格式，不依赖此对齐。
    func syncFromStorage(_ storage: NSTextStorage) {
        ranges = Self.paragraphRanges(of: storage.string)
        if formats.count > ranges.count {
            formats.removeLast(formats.count - ranges.count)
        }
        while formats.count < ranges.count {
            formats.append(.body)
        }
    }

    /// 从属性推导全部格式（RTFD 草稿恢复、富文本粘贴后的模型重建）。
    func deriveFormats(from storage: NSTextStorage) {
        syncFromStorage(storage)
        let string = storage.string as NSString
        for index in ranges.indices {
            formats[index] = Self.deriveFormat(of: ranges[index], in: storage, string: string)
        }
    }

    private static func deriveFormat(of range: NSRange, in storage: NSTextStorage, string: NSString) -> ParagraphFormat {
        guard range.length > 0 else { return .body }
        let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        if let lists = style?.textLists, !lists.isEmpty {
            return ParagraphFormat(
                kind: .listItem,
                listLevel: min(lists.count, ListLayout.maxLevel),
                ordered: lists.last?.markerFormat == .decimal
            )
        }
        let contentRange = contentRange(of: range, in: string)
        guard contentRange.length > 0 else { return .body }

        var hasTextRun = false
        var uniformBoldSize: CGFloat?
        var allCode = true
        storage.enumerateAttribute(.font, in: contentRange) { value, subrange, stop in
            let text = string.substring(with: subrange).replacingOccurrences(of: "\u{FFFC}", with: "")
            guard !text.isEmpty else { return }
            hasTextRun = true
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: HTMLExporter.bodyFontSize)
            let isBold = NSFontManager.shared.traits(of: font).contains(.boldFontMask)
            let size: CGFloat? = isBold ? font.pointSize : nil
            if let current = uniformBoldSize {
                if current != size { uniformBoldSize = 0 }
            } else {
                uniformBoldSize = size
            }
            if !HTMLExporter.isCodeFont(font) { allCode = false }
            if uniformBoldSize == 0 && !allCode { stop.pointee = true }
        }
        guard hasTextRun else { return .body }
        if let size = uniformBoldSize, size > 0 {
            if size >= HTMLExporter.h1FontSize - 1 { return ParagraphFormat(kind: .h1) }
            if size >= HTMLExporter.h2FontSize - 1 { return ParagraphFormat(kind: .h2) }
            return ParagraphFormat(kind: .h3)
        }
        if allCode { return ParagraphFormat(kind: .codeBlock) }
        return .body
    }

    static func contentRange(of paragraphRange: NSRange, in string: NSString) -> NSRange {
        var length = paragraphRange.length
        while length > 0 {
            let last = string.character(at: paragraphRange.location + length - 1)
            guard let scalar = Unicode.Scalar(last), CharacterSet.newlines.contains(scalar) else { break }
            length -= 1
        }
        return NSRange(location: paragraphRange.location, length: length)
    }
}
