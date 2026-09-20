import AppKit

/// 编辑器唯一格式写入口（EditorSpec §11）：所有格式变更经此类，变更后
/// model → attributes 单向同步。SwiftUI 直接观察此类（@Published images 等）。
final class EditorCore: ObservableObject {
    let document = EditorDocument()
    weak var textView: EditorTextView?

    /// 编辑区内抽出的图片附件（粘贴/拖入），保存时作为备忘录附件。
    @Published private(set) var images: [NSImage] = []

    /// 程序化变更标记：期间不做 selection 驱动的 typingAttributes 归一。
    private(set) var isMutating = false

    static let lineSpacing: CGFloat = 4
    static var defaultFont: NSFont { NSFont.systemFont(ofSize: HTMLExporter.bodyFontSize) }

    static func baseParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

    static var defaultTypingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: defaultFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: baseParagraphStyle(),
        ]
    }

    static func headingFont(_ level: Int) -> NSFont {
        switch level {
        case 1: return NSFont.boldSystemFont(ofSize: HTMLExporter.h1FontSize)
        case 2: return NSFont.boldSystemFont(ofSize: HTMLExporter.h2FontSize)
        default: return NSFont.boldSystemFont(ofSize: HTMLExporter.bodyFontSize)
        }
    }

    static func isHeadingFont(_ font: NSFont) -> Bool {
        NSFontManager.shared.traits(of: font).contains(.boldFontMask)
            && font.pointSize >= HTMLExporter.h2FontSize - 1
    }

    // MARK: - 查询

    var isEmpty: Bool {
        guard let storage = textView?.textStorage else { return true }
        let text = storage.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty && images.isEmpty
    }

    func syncFromStorage() {
        guard let storage = textView?.textStorage else { return }
        document.syncFromStorage(storage)
    }

    func cursorParagraphIndex() -> Int {
        guard let textView else { return 0 }
        return document.paragraphIndex(atLocation: textView.selectedRange().location)
    }

    func cursorFormat() -> ParagraphFormat {
        document.format(at: cursorParagraphIndex())
    }

    /// 段落去掉末尾换行后是否无内容（空段落）。
    func isParagraphContentEmpty(at index: Int) -> Bool {
        guard let storage = textView?.textStorage else { return true }
        return EditorDocument.contentRange(
            of: document.paragraphRange(at: index),
            in: storage.string as NSString
        ).length == 0
    }

    // MARK: - Undo 快照

    func snapshotForUndo() {
        guard let textView, let storage = textView.textStorage else { return }
        UndoSupport.registerSnapshot(storage: storage, document: document, textView: textView)
    }

    private func withMutation(_ body: () -> Void) {
        isMutating = true
        body()
        isMutating = false
    }

    // MARK: - model → attributes 单向同步

    func paragraphStyle(for format: ParagraphFormat) -> NSParagraphStyle {
        let style = Self.baseParagraphStyle()
        if format.isList {
            let marker: NSTextList.MarkerFormat = format.ordered ? .decimal : .disc
            style.textLists = (0..<format.listLevel).map { _ in
                NSTextList(markerFormat: marker, options: 0)
            }
            style.firstLineHeadIndent = ListLayout.headIndent(level: format.listLevel)
            style.headIndent = style.firstLineHeadIndent
        }
        return style
    }

    /// 应用单段段落样式（空段落无字符可挂样式，格式只在模型里，标记由 MarkerRenderer 画）。
    func applyParagraphStyle(at index: Int) {
        guard let storage = textView?.textStorage else { return }
        let range = document.paragraphRange(at: index)
        guard range.length > 0 else { return }
        storage.addAttribute(.paragraphStyle, value: paragraphStyle(for: document.format(at: index)), range: range)
    }

    /// 标题/代码块段落整段字体；正文/列表项从标题或代码降级时整段归位正文。
    func applyFont(at index: Int) {
        guard let storage = textView?.textStorage else { return }
        let format = document.format(at: index)
        let range = EditorDocument.contentRange(of: document.paragraphRange(at: index), in: storage.string as NSString)
        guard range.length > 0 else { return }
        switch format.kind {
        case .h1: storage.addAttribute(.font, value: Self.headingFont(1), range: range)
        case .h2: storage.addAttribute(.font, value: Self.headingFont(2), range: range)
        case .h3: storage.addAttribute(.font, value: Self.headingFont(3), range: range)
        case .codeBlock: storage.addAttribute(.font, value: HTMLExporter.codeFont, range: range)
        case .body, .listItem:
            storage.addAttribute(.font, value: Self.defaultFont, range: range)
        }
    }

    /// 全部段落样式重刷（幂等；段落级属性与行内属性正交，不会破坏粗斜体等）。
    func applyAllParagraphStyles() {
        for index in 0..<document.paragraphCount {
            applyParagraphStyle(at: index)
        }
    }

    // MARK: - 文本变更后的同步（delegate textDidChange 调用）

    func handleTextChanged() {
        guard let textView, let storage = textView.textStorage else { return }
        document.syncFromStorage(storage)
        if !textView.hasMarkedText() {
            applyAllParagraphStyles()
        }
        collectAttachments()
        schedulePersistDraft()
        objectWillChange.send()
    }

    // MARK: - 光标所在段落类型的输入字体归一（selection 变化时调用）

    func updateTypingAttributesForCursor() {
        guard let textView, !textView.hasMarkedText(), !isMutating else { return }
        syncFromStorage()
        let kind = cursorFormat().kind
        var attributes = textView.typingAttributes
        switch kind {
        case .h1: attributes[.font] = Self.headingFont(1)
        case .h2: attributes[.font] = Self.headingFont(2)
        case .h3: attributes[.font] = Self.headingFont(3)
        case .codeBlock: attributes[.font] = HTMLExporter.codeFont
        case .body, .listItem:
            // 从标题/代码段落移出时回归正文；正文内的粗斜体保留
            if let current = attributes[.font] as? NSFont,
               Self.isHeadingFont(current) || HTMLExporter.isCodeFont(current) {
                attributes[.font] = Self.defaultFont
            }
        }
        textView.typingAttributes = attributes
    }

    // MARK: - 结构原语

    /// 插入换行并把新段落设为指定格式（Enter 矩阵的唯一落点）。
    func insertNewline(withFormat newFormat: ParagraphFormat, typingFont: NSFont) {
        guard let textView, let storage = textView.textStorage else { return }
        withMutation {
            snapshotForUndo()
            let index = cursorParagraphIndex()
            let range = textView.selectedRange()
            if textView.shouldChangeText(in: range, replacementString: "\n") {
                storage.replaceCharacters(in: range, with: "\n")
                textView.didChangeText()
            }
            document.insertFormat(newFormat, atParagraph: index + 1)
            document.syncFromStorage(storage)
            applyParagraphStyle(at: index + 1)
            if newFormat.kind == .codeBlock || newFormat.kind == .h1 || newFormat.kind == .h2 || newFormat.kind == .h3 {
                applyFont(at: index + 1)
            }
            textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            var attributes = textView.typingAttributes
            attributes[.font] = typingFont
            textView.typingAttributes = attributes
            textView.needsDisplay = true
        }
    }

    /// 正文段落首退格：删除上一段落末尾换行符合并段落（系统默认行为的显式实现）。
    func mergeWithPreviousParagraph(at index: Int) {
        guard let textView, let storage = textView.textStorage, index > 0 else { return }
        withMutation {
            snapshotForUndo()
            let newlineLocation = document.paragraphRange(at: index).location - 1
            guard newlineLocation >= 0, newlineLocation < storage.length else { return }
            if textView.shouldChangeText(in: NSRange(location: newlineLocation, length: 1), replacementString: "") {
                storage.replaceCharacters(in: NSRange(location: newlineLocation, length: 1), with: "")
                textView.didChangeText()
            }
            document.removeFormat(atParagraph: index)
            document.syncFromStorage(storage)
            textView.setSelectedRange(NSRange(location: newlineLocation, length: 0))
            textView.needsDisplay = true
        }
    }

    /// 标题/代码块降级为正文（不删字符）。
    func degradeToBody(at index: Int) {
        withMutation {
            snapshotForUndo()
            let previous = document.format(at: index)
            document.setFormat(.body, atParagraph: index)
            applyParagraphStyle(at: index)
            if previous.kind != .body && previous.kind != .listItem {
                applyFont(at: index)
            }
            var attributes = textView?.typingAttributes ?? [:]
            attributes[.font] = Self.defaultFont
            textView?.typingAttributes = attributes
            textView?.needsDisplay = true
        }
    }

    /// 列表项提升一层；最外层退出列表为正文。
    func outdentOrExitList(at index: Int) {
        withMutation {
            snapshotForUndo()
            var format = document.format(at: index)
            guard format.isList else { return }
            if format.listLevel > 1 {
                format.listLevel -= 1
                document.setFormat(format, atParagraph: index)
            } else {
                document.setFormat(.body, atParagraph: index)
            }
            applyParagraphStyle(at: index)
            textView?.needsDisplay = true
        }
    }

    /// 列表项降低一层（上限 ListLayout.maxLevel）。
    func indentList(at index: Int) {
        withMutation {
            snapshotForUndo()
            var format = document.format(at: index)
            guard format.isList, format.listLevel < ListLayout.maxLevel else { return }
            format.listLevel += 1
            document.setFormat(format, atParagraph: index)
            applyParagraphStyle(at: index)
            textView?.needsDisplay = true
        }
    }

    // MARK: - 块级格式操作（工具栏 / 触发转换共用）

    /// level：0 正文、1 H1、2 H2、3 H3。作用于选区覆盖的全部段落。
    func applyHeading(_ level: Int) {
        guard let textView, textView.textStorage != nil else { return }
        withMutation {
            syncFromStorage()
            snapshotForUndo()
            let kind: ParagraphFormat.Kind = switch level {
            case 1: .h1
            case 2: .h2
            case 3: .h3
            default: .body
            }
            for index in paragraphIndicesCovered(by: textView.selectedRange()) {
                let wasSpecial = switch document.format(at: index).kind {
                case .h1, .h2, .h3, .codeBlock: true
                default: false
                }
                document.setFormat(ParagraphFormat(kind: kind), atParagraph: index)
                applyParagraphStyle(at: index)
                if kind != .body || wasSpecial {
                    applyFont(at: index)
                }
            }
            var attributes = textView.typingAttributes
            attributes[.font] = level > 0 ? Self.headingFont(level) : Self.defaultFont
            textView.typingAttributes = attributes
            textView.needsDisplay = true
        }
    }

    func toggleList(ordered: Bool) {
        guard let textView, textView.textStorage != nil else { return }
        withMutation {
            syncFromStorage()
            snapshotForUndo()
            let indices = paragraphIndicesCovered(by: textView.selectedRange())
            let allSameList = indices.allSatisfy { index in
                let format = document.format(at: index)
                return format.isList && format.ordered == ordered
            }
            for index in indices {
                let format: ParagraphFormat = allSameList
                    ? .body
                    : ParagraphFormat(kind: .listItem, listLevel: 1, ordered: ordered)
                document.setFormat(format, atParagraph: index)
                applyParagraphStyle(at: index)
            }
            textView.needsDisplay = true
        }
    }

    func toggleCodeBlock() {
        guard let textView, textView.textStorage != nil else { return }
        withMutation {
            syncFromStorage()
            snapshotForUndo()
            let indices = paragraphIndicesCovered(by: textView.selectedRange())
            let allCode = indices.allSatisfy { document.format(at: $0).kind == .codeBlock }
            for index in indices {
                document.setFormat(ParagraphFormat(kind: allCode ? .body : .codeBlock), atParagraph: index)
                applyParagraphStyle(at: index)
                applyFont(at: index)
            }
            var attributes = textView.typingAttributes
            attributes[.font] = allCode ? Self.defaultFont : HTMLExporter.codeFont
            textView.typingAttributes = attributes
            textView.needsDisplay = true
        }
    }

    /// 选区覆盖的段落下标范围（空选区 = 光标段落）。
    func paragraphIndicesCovered(by range: NSRange) -> ClosedRange<Int> {
        syncFromStorage()
        let first = document.paragraphIndex(atLocation: range.location)
        guard range.length > 0 else { return first...first }
        let endLocation = max(range.location, NSMaxRange(range) - 1)
        let last = document.paragraphIndex(atLocation: endLocation)
        return first...max(first, last)
    }

    // MARK: - 行内格式

    func toggleBold() { toggleFontTrait(.boldFontMask) }
    func toggleItalic() { toggleItalicObliqueness() }
    func toggleUnderline() { toggleStyleAttribute(.underlineStyle) }
    func toggleStrikethrough() { toggleStyleAttribute(.strikethroughStyle) }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView, let storage = textView.textStorage else { return }
        snapshotForUndo()
        let range = textView.selectedRange()
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let font = attributes[.font] as? NSFont ?? Self.defaultFont
            attributes[.font] = Self.font(font, toggling: trait)
            textView.typingAttributes = attributes
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? Self.defaultFont
            storage.addAttribute(.font, value: Self.font(font, toggling: trait), range: subrange)
        }
        storage.endEditing()
    }

    private static func font(_ font: NSFont, toggling trait: NSFontTraitMask) -> NSFont {
        let manager = NSFontManager.shared
        if manager.traits(of: font).contains(trait) {
            return manager.convert(font, toNotHaveTrait: trait)
        }
        return manager.convert(font, toHaveTrait: trait)
    }

    /// 斜体用合成倾斜（obliqueness）而非字体 italic trait：中文等 CJK 字体没有斜体变体。
    private func toggleItalicObliqueness() {
        guard let textView, let storage = textView.textStorage else { return }
        snapshotForUndo()
        let slant: Float = 0.25

        func toggled(_ attributes: inout [NSAttributedString.Key: Any]) {
            let obliqueness = (attributes[.obliqueness] as? NSNumber)?.floatValue ?? 0
            let font = attributes[.font] as? NSFont
            let hasItalicTrait = font.map {
                NSFontManager.shared.traits(of: $0).contains(.italicFontMask)
            } ?? false
            if obliqueness > 0 || hasItalicTrait {
                attributes.removeValue(forKey: .obliqueness)
                if let font, hasItalicTrait {
                    attributes[.font] = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                }
            } else {
                attributes[.obliqueness] = slant
            }
        }

        let range = textView.selectedRange()
        if range.length == 0 {
            var attributes = textView.typingAttributes
            toggled(&attributes)
            textView.typingAttributes = attributes
            return
        }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attributes, subrange, _ in
            var attributes = attributes
            toggled(&attributes)
            storage.setAttributes(attributes, range: subrange)
        }
        storage.endEditing()
    }

    private func toggleStyleAttribute(_ key: NSAttributedString.Key) {
        guard let textView, let storage = textView.textStorage else { return }
        snapshotForUndo()
        let range = textView.selectedRange()
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let current = (attributes[key] as? Int) ?? 0
            if current == 0 {
                attributes[key] = NSUnderlineStyle.single.rawValue
            } else {
                attributes.removeValue(forKey: key)
            }
            textView.typingAttributes = attributes
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(key, in: range) { value, subrange, _ in
            let current = (value as? Int) ?? 0
            if current == 0 {
                storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: subrange)
            } else {
                storage.removeAttribute(key, range: subrange)
            }
        }
        storage.endEditing()
    }

    /// 行内格式直接应用（Markdown 配对转换用；无 toggle 语义）。
    func applyInlineFormat(_ format: MarkdownTriggers.InlineFormat, in range: NSRange) {
        guard let storage = textView?.textStorage, range.length > 0 else { return }
        storage.beginEditing()
        switch format {
        case .bold:
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = (value as? NSFont) ?? Self.defaultFont
                storage.addAttribute(
                    .font,
                    value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask),
                    range: subrange
                )
            }
        case .italic:
            storage.addAttribute(.obliqueness, value: Float(0.25), range: range)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .code:
            storage.addAttribute(.font, value: HTMLExporter.codeFont, range: range)
        }
        storage.endEditing()
    }

    // MARK: - 行内代码边界（EditorSpec §3.1 泄漏规则的补充：点击到既有代码段之后）

    /// 光标紧邻代码 run 末尾（之后不是代码）时，输入回归正文字体；
    /// 光标在代码段内部（之后仍是代码）保持等宽。代码 run 从段首开始则视为代码块，不重置。
    func normalizeCodeFontAtBoundary() {
        guard let textView, let storage = textView.textStorage,
              textView.selectedRange().length == 0,
              let typingFont = textView.typingAttributes[.font] as? NSFont,
              HTMLExporter.isCodeFont(typingFont) else { return }
        let location = textView.selectedRange().location
        guard location > 0 else { return }
        let string = storage.string as NSString
        var runRange = NSRange()
        guard let beforeFont = storage.attribute(.font, at: location - 1, effectiveRange: &runRange) as? NSFont,
              HTMLExporter.isCodeFont(beforeFont) else { return }
        if location < storage.length,
           let afterFont = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont,
           HTMLExporter.isCodeFont(afterFont) { return }
        let paragraphStart = string.paragraphRange(for: NSRange(location: location - 1, length: 0)).location
        guard runRange.location > paragraphStart else { return }
        var attributes = textView.typingAttributes
        attributes[.font] = Self.defaultFont
        textView.typingAttributes = attributes
    }

    // MARK: - Markdown 触发（EditorSpec §3.1）

    /// 块级触发：输入空格后调用。条件：光标在段落行首、段落为正文（不在列表项/代码块内）。
    func convertBlockMarkerIfNeeded() {
        guard let textView, let storage = textView.textStorage else { return }
        syncFromStorage()
        let cursor = textView.selectedRange().location
        guard cursor >= 2 else { return }
        let index = document.paragraphIndex(atLocation: cursor - 1)
        guard document.format(at: index).kind == .body else { return }
        let paragraphStart = document.paragraphRange(at: index).location
        let prefix = (storage.string as NSString).substring(
            with: NSRange(location: paragraphStart, length: cursor - paragraphStart)
        )
        guard let action = MarkdownTriggers.blockAction(paragraphPrefix: prefix) else { return }

        withMutation {
            snapshotForUndo()
            // 删除引起的选区同步会从上一行末尾字符继承字体，恢复为输入标记时的输入属性
            let savedTypingAttributes = textView.typingAttributes
            let markerRange = NSRange(location: paragraphStart, length: cursor - paragraphStart)
            if textView.shouldChangeText(in: markerRange, replacementString: "") {
                storage.replaceCharacters(in: markerRange, with: "")
                textView.didChangeText()
            }
            textView.setSelectedRange(NSRange(location: paragraphStart, length: 0))
            textView.typingAttributes = savedTypingAttributes

            switch action {
            case .heading(let level):
                let kind: ParagraphFormat.Kind = level == 1 ? .h1 : level == 2 ? .h2 : .h3
                document.setFormat(ParagraphFormat(kind: kind), atParagraph: index)
                applyParagraphStyle(at: index)
                applyFont(at: index)
                var attributes = textView.typingAttributes
                attributes[.font] = Self.headingFont(level)
                textView.typingAttributes = attributes
            case .unorderedList, .orderedList:
                document.setFormat(
                    ParagraphFormat(kind: .listItem, listLevel: 1, ordered: action == .orderedList),
                    atParagraph: index
                )
                applyParagraphStyle(at: index)
            case .codeBlock:
                document.setFormat(ParagraphFormat(kind: .codeBlock), atParagraph: index)
                applyParagraphStyle(at: index)
                applyFont(at: index)
                var attributes = textView.typingAttributes
                attributes[.font] = HTMLExporter.codeFont
                textView.typingAttributes = attributes
            }
            textView.needsDisplay = true
        }
    }

    /// 行内配对触发：输入闭合符后调用。命中后删除标记、应用格式，
    /// 光标落在内容之后且输入属性复位为正文默认（§3.1：行内格式永不向后泄漏）。
    func convertInlinePairIfNeeded() {
        guard let textView, let storage = textView.textStorage else { return }
        let cursor = textView.selectedRange().location
        syncFromStorage()
        let paragraphStart = document.paragraphRange(
            at: document.paragraphIndex(atLocation: max(0, cursor - 1))
        ).location
        guard cursor > paragraphStart else { return }
        let lineText = (storage.string as NSString).substring(
            with: NSRange(location: paragraphStart, length: cursor - paragraphStart)
        )
        guard let match = MarkdownTriggers.inlineMatch(lineText: lineText) else { return }

        withMutation {
            snapshotForUndo()
            let contentRange = NSRange(
                location: paragraphStart + match.contentRange.location,
                length: match.contentRange.length
            )
            let openRange = NSRange(
                location: paragraphStart + match.openMarkerRange.location,
                length: match.openMarkerRange.length
            )
            let closeRange = NSRange(
                location: paragraphStart + match.closeMarkerRange.location,
                length: match.closeMarkerRange.length
            )
            applyInlineFormat(match.format, in: contentRange)
            storage.deleteCharacters(in: closeRange)
            storage.deleteCharacters(in: openRange)
            textView.setSelectedRange(NSRange(location: openRange.location + contentRange.length, length: 0))
            textView.typingAttributes = Self.defaultTypingAttributes
            textView.needsDisplay = true
        }
    }

    // MARK: - 图片收集

    func collectAttachments() {
        guard let storage = textView?.textStorage else { return }
        var collected: [NSImage] = []
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let image = Self.image(from: attachment) else { return }
            collected.append(image)
            // 编辑区内仅显示缩略占位（≤72px 保持宽高比），不做图文混排排版。
            if attachment.bounds == .zero {
                let size = image.size
                guard size.width > 0, size.height > 0 else { return }
                let maxHeight: CGFloat = 72
                let scale = min(1, maxHeight / size.height)
                attachment.bounds = CGRect(
                    x: 0, y: 0,
                    width: size.width * scale,
                    height: size.height * scale
                )
                textView?.layoutManager?.invalidateLayout(
                    forCharacterRange: range,
                    actualCharacterRange: nil
                )
            }
        }
        images = collected
    }

    private static func image(from attachment: NSTextAttachment) -> NSImage? {
        if let image = attachment.image { return image }
        if let data = attachment.fileWrapper?.regularFileContents,
           let image = NSImage(data: data) { return image }
        if let data = attachment.contents,
           let image = NSImage(data: data) { return image }
        return nil
    }

    // MARK: - 内容导出与清空

    func exportContent() -> NotesSaver.NoteContent? {
        guard let storage = textView?.textStorage, !isEmpty else { return nil }
        let exported = HTMLExporter.export(storage, document: document)
        return NotesSaver.NoteContent(
            title: exported.title,
            bodyHTML: exported.bodyHTML,
            images: images
        )
    }

    func clear() {
        guard let textView, let storage = textView.textStorage else { return }
        withMutation {
            storage.setAttributedString(NSAttributedString())
            document.restoreFormats([.body])
            document.syncFromStorage(storage)
            textView.typingAttributes = Self.defaultTypingAttributes
            images.removeAll()
            persistDraft()
        }
        objectWillChange.send()
    }

    // MARK: - 草稿持久化（保存成功或删空内容时才清除）

    /// 沙盒容器内 Application Support/NoteMenu/draft.rtfd。
    private static let draftURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("NoteMenu/draft.rtfd")
    }()

    private var pendingPersist: DispatchWorkItem?

    /// 立即将编辑内容（含图片附件）序列化为 RTFD 落盘；内容为空时删除草稿文件。
    func persistDraft() {
        pendingPersist?.cancel()
        pendingPersist = nil
        guard let storage = textView?.textStorage else { return }
        let url = Self.draftURL
        do {
            if isEmpty {
                try FileManager.default.removeItem(at: url)
            } else {
                guard let data = storage.rtfd(
                    from: NSRange(location: 0, length: storage.length),
                    documentAttributes: [:]
                ) else { return }
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // 草稿写入失败不打断输入，下次内容变化时会重试。
        }
    }

    /// 防抖调度草稿持久化：输入停止 1 秒后才落盘。
    func schedulePersistDraft() {
        pendingPersist?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistDraft() }
        pendingPersist = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// 浮窗失焦或 App 退出前调用：若有未落盘的防抖写入则立即执行。
    func flushPendingPersist() {
        guard pendingPersist != nil else { return }
        persistDraft()
    }

    /// 启动时恢复上次未保存的草稿：RTFD 还原属性后重建模型（EditorSpec §11 同步边界）。
    func restoreDraft() {
        guard let textView, let storage = textView.textStorage, storage.length == 0,
              let data = try? Data(contentsOf: Self.draftURL),
              let draft = try? NSAttributedString(rtfd: data, documentAttributes: nil),
              draft.length > 0 else { return }
        storage.setAttributedString(draft)
        document.deriveFormats(from: storage)
        collectAttachments()
        objectWillChange.send()
    }
}
