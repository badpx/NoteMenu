import AppKit
import SwiftUI

/// 列表项排水区宽度（标记绘制与段落缩进共用）。
private let listIndent: CGFloat = 22

/// 编辑器状态：承载 NSTextView 引用，向外暴露格式化指令与内容导出。
final class NoteEditorModel: ObservableObject {
    static let defaultFont = NSFont.systemFont(ofSize: 14)

    fileprivate weak var textView: NSTextView?
    /// 编辑区内抽出的图片附件（粘贴/拖入），保存时作为备忘录附件。
    private(set) var images: [NSImage] = []

    var isEmpty: Bool {
        guard let storage = textView?.textStorage else { return true }
        let text = storage.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty && images.isEmpty
    }

    // MARK: - 草稿持久化（保存成功或删空内容时才清除）

    /// 沙盒容器内 Application Support/NoteMenu/draft.rtfd。
    private static let draftURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("NoteMenu/draft.rtfd")
    }()

    /// 草稿防抖写入任务：连续输入合并为一次落盘。
    private var pendingPersist: DispatchWorkItem?

    /// 立即将编辑内容（含图片附件）序列化为 RTFD 落盘；内容为空时删除草稿文件。
    /// 会取消并覆盖任何待执行的防抖写入。
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

    /// 防抖调度草稿持久化：输入停止 1 秒后才落盘，避免每次按键全量写文件。
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

    /// 启动时恢复上次未保存的草稿。
    func restoreDraft() {
        guard let textView, let storage = textView.textStorage, storage.length == 0,
              let data = try? Data(contentsOf: Self.draftURL),
              let draft = try? NSAttributedString(rtfd: data, documentAttributes: nil),
              draft.length > 0 else { return }
        storage.setAttributedString(draft)
        collectAttachments()
        objectWillChange.send()
    }

    // MARK: - 内容导出与清空

    func exportContent() -> NotesSaver.NoteContent? {
        guard let storage = textView?.textStorage, !isEmpty else { return nil }
        let exported = HTMLExporter.export(storage)
        return NotesSaver.NoteContent(
            title: exported.title,
            bodyHTML: exported.bodyHTML,
            images: images
        )
    }

    func clear() {
        guard let textView, let storage = textView.textStorage else { return }
        storage.setAttributedString(NSAttributedString())
        textView.typingAttributes = [
            .font: Self.defaultFont,
            .foregroundColor: NSColor.textColor,
        ]
        images.removeAll()
        persistDraft()
        objectWillChange.send()
    }

    // MARK: - 编辑区内图片收集

    fileprivate func collectAttachments() {
        guard let storage = textView?.textStorage else { return }
        var collected: [NSImage] = []
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let image = Self.image(from: attachment) else { return }
            collected.append(image)
            // 编辑区内仅显示缩略占位，不做图文混排排版。
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

    // MARK: - 加粗 / 斜体 / 下划线

    func toggleBold() { toggleFontTrait(.boldFontMask) }

    /// 斜体用合成倾斜（obliqueness）而非字体 italic trait：
    /// 中文等 CJK 字体没有斜体变体，字体替换会把 italic trait 丢掉。
    func toggleItalic() {
        guard let textView, let storage = textView.textStorage else { return }
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

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView, let storage = textView.textStorage else { return }
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

    func toggleUnderline() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let current = (attributes[.underlineStyle] as? Int) ?? 0
            if current == 0 {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                attributes.removeValue(forKey: .underlineStyle)
            }
            textView.typingAttributes = attributes
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.underlineStyle, in: range) { value, subrange, _ in
            let current = (value as? Int) ?? 0
            if current == 0 {
                storage.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: subrange
                )
            } else {
                storage.removeAttribute(.underlineStyle, range: subrange)
            }
        }
        storage.endEditing()
    }

    // MARK: - 列表（NSTextList）

    func toggleList(_ markerFormat: NSTextList.MarkerFormat) {
        guard let textView, let storage = textView.textStorage else { return }

        func updatedStyle(from base: NSParagraphStyle?) -> NSParagraphStyle {
            let style = (base?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            if style.textLists.first?.markerFormat == markerFormat {
                style.textLists = []
                style.firstLineHeadIndent = 0
                style.headIndent = 0
            } else {
                style.textLists = [NSTextList(markerFormat: markerFormat, options: 0)]
                style.firstLineHeadIndent = listIndent
                style.headIndent = listIndent
            }
            return style
        }

        let range = textView.selectedRange()

        // 光标处的输入属性：保证空文档、继续输入与换行时列表延续。
        let cursorStyle: NSParagraphStyle?
        if storage.length > 0 {
            let location = min(range.location, storage.length - 1)
            cursorStyle = (storage.attribute(.paragraphStyle, at: location, effectiveRange: nil)
                ?? textView.typingAttributes[.paragraphStyle]) as? NSParagraphStyle
        } else {
            cursorStyle = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        }
        var typingAttributes = textView.typingAttributes
        typingAttributes[.paragraphStyle] = updatedStyle(from: cursorStyle)
        textView.typingAttributes = typingAttributes

        // 应用到光标/选区所在的已有段落。
        guard storage.length > 0 else {
            textView.needsDisplay = true
            return
        }
        let paragraphRange = (storage.string as NSString).paragraphRange(for: range)
        guard paragraphRange.length > 0 else {
            textView.needsDisplay = true
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, subrange, _ in
            storage.addAttribute(
                .paragraphStyle,
                value: updatedStyle(from: value as? NSParagraphStyle),
                range: subrange
            )
        }
        storage.endEditing()
        textView.needsDisplay = true
    }
}

/// 带占位文字的富文本编辑框。
/// NSTextView 不渲染 NSTextList 标记（TextEdit 的列表符号是自行绘制的），
/// 因此这里手动绘制 •/N. 标记，并拦截图片粘贴以保证附件带有真实图像数据。
private final class EditorTextView: NSTextView {
    var placeholder: String = "现在的想法是…"

    // MARK: - 绘制（占位文字 + 列表标记）

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawListMarkers()
        drawPlaceholderIfNeeded()
    }

    private func drawPlaceholderIfNeeded() {
        guard string.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NoteEditorModel.defaultFont,
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        // 占位文字跟随输入属性的段落样式（如空文档下开启列表的缩进），与光标起点保持一致。
        if let style = typingAttributes[.paragraphStyle] as? NSParagraphStyle {
            attributes[.paragraphStyle] = style
        }
        let inset = textContainerInset
        let linePadding = textContainer?.lineFragmentPadding ?? 0
        let rect = NSRect(
            x: inset.width + linePadding,
            y: inset.height,
            width: bounds.width - inset.width - linePadding * 2,
            height: bounds.height - inset.height
        )
        placeholder.draw(in: rect, withAttributes: attributes)
    }

    private func drawListMarkers() {
        guard let layoutManager, let textContainer,
              let storage = textStorage, storage.length > 0 else { return }
        layoutManager.ensureLayout(for: textContainer)

        let string = storage.string as NSString
        let gutterX = textContainerInset.width + textContainer.lineFragmentPadding
        var lastMarker: NSTextList.MarkerFormat?
        var number = 0

        var location = 0
        while location < string.length {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(paragraphRange)

            guard let style = storage.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle,
                  let list = style.textLists.first else {
                lastMarker = nil
                number = 0
                continue
            }

            if list.markerFormat == lastMarker {
                number += 1
            } else {
                number = max(1, list.startingItemNumber)
            }
            lastMarker = list.markerFormat

            let marker: String
            switch list.markerFormat {
            case .decimal: marker = "\(number)."
            default: marker = "•"
            }

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: paragraphRange.location)
            guard glyphIndex < layoutManager.numberOfGlyphs else { continue }
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

            let markerFont = (storage.attribute(.font, at: paragraphRange.location, effectiveRange: nil) as? NSFont)
                ?? font ?? NoteEditorModel.defaultFont
            let attributes: [NSAttributedString.Key: Any] = [
                .font: markerFont,
                .foregroundColor: NSColor.textColor,
            ]
            let markerSize = (marker as NSString).size(withAttributes: attributes)
            // baselineOffset 是基线到行框底部的距离；
            // draw(at:) 的点对应字形 ascender 顶端（基线在点下方 ascender 处）。
            let baseline = lineRect.maxY
                - layoutManager.typesetter.baselineOffset(in: layoutManager, glyphIndex: glyphIndex)
            let point = NSPoint(
                x: gutterX + listIndent - 4 - markerSize.width,
                y: textContainerInset.height + baseline - markerFont.ascender
            )
            (marker as NSString).draw(at: point, withAttributes: attributes)
        }
    }

    // MARK: - 回车：列表延续 / 空列表项退出列表

    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage, storage.length > 0 else {
            super.insertNewline(sender)
            return
        }
        let location = min(selectedRange().location, storage.length - 1)
        let paragraphRange = (storage.string as NSString).paragraphRange(
            for: NSRange(location: location, length: 0)
        )
        // 只含换行符的空列表段落：回车转为普通段落而不是继续列表。
        let isEmptyParagraph = paragraphRange.length <= 1
        if isEmptyParagraph,
           let style = storage.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle,
           !style.textLists.isEmpty {
            guard let plain = style.mutableCopy() as? NSMutableParagraphStyle else {
                super.insertNewline(sender)
                return
            }
            plain.textLists = []
            plain.firstLineHeadIndent = 0
            plain.headIndent = 0
            storage.addAttribute(.paragraphStyle, value: plain, range: paragraphRange)
            var attributes = typingAttributes
            attributes[.paragraphStyle] = plain
            typingAttributes = attributes
            needsDisplay = true
            return
        }
        // 非空列表段落：typingAttributes 中的段落样式随换行延续到新段落。
        super.insertNewline(sender)
    }

    // MARK: - 粘贴：保证图片附件带有真实图像数据

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let images = Self.imagesOnPasteboard(pasteboard)
        if !images.isEmpty {
            for image in images {
                insertImageAttachment(image)
            }
            return
        }
        super.paste(sender)
    }

    /// 仅当剪贴板直接携带图像数据（截图/“拷贝图像”）或图像文件 URL（Finder 复制）时拦截；
    /// 其余（纯文本、富文本）走默认粘贴逻辑。
    private static func imagesOnPasteboard(_ pasteboard: NSPasteboard) -> [NSImage] {
        var images: [NSImage] = []
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                images.append(image)
            }
        }
        if !images.isEmpty { return images }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            for url in urls {
                if let image = NSImage(contentsOf: url) {
                    images.append(image)
                }
            }
        }
        return images
    }

    private func insertImageAttachment(_ image: NSImage) {
        guard let png = NotesSaver.pngData(for: image) else { return }
        let attachment = NSTextAttachment(data: png, ofType: "public.png")
        attachment.image = image
        let attributed = NSAttributedString(attachment: attachment)
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: attributed.string) else { return }
        textStorage?.replaceCharacters(in: range, with: attributed)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + attributed.length, length: 0))
    }
}

struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var model: NoteEditorModel

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = EditorTextView()
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = false
        textView.font = NoteEditorModel.defaultFont
        textView.textColor = .textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        model.textView = textView
        model.restoreDraft()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let model: NoteEditorModel
        private var observers: [NSObjectProtocol] = []

        init(model: NoteEditorModel) {
            self.model = model
            super.init()
            // 浮窗失焦（含收起）与 App 退出时，立即落盘未写入的草稿。
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self,
                      (notification.object as? NSWindow) === self.model.textView?.window else { return }
                self.model.flushPendingPersist()
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.model.flushPendingPersist()
            })
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func textDidChange(_ notification: Notification) {
            // 内容删空后复位输入属性，避免残留的列表缩进等段落样式把光标带离行首。
            if let textView = notification.object as? NSTextView, textView.string.isEmpty {
                textView.typingAttributes = [
                    .font: NoteEditorModel.defaultFont,
                    .foregroundColor: NSColor.textColor,
                ]
            }
            model.collectAttachments()
            model.schedulePersistDraft()
            model.objectWillChange.send()
        }
    }
}
