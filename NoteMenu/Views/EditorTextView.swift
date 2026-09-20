import AppKit
import SwiftUI

/// 薄壳编辑器（EditorSpec §11）：NSTextView 子类只负责事件接入与绘制回调，
/// 逻辑全部下沉 Editor/ 模块（Core/Router/Triggers/Renderer/Sanitizer）。
final class EditorTextView: NSTextView {
    var placeholder: String = "现在的想法是…"
    var onSave: (() -> Void)?
    var core: EditorCore?

    // MARK: - 快捷键（§3.2；IME 组合中不拦截 §7.2）

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let core, let onSave,
           KeyEventRouter.handleKeyEquivalent(event, core: core, textView: self, onSave: onSave) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - 文本输入（IME 组合中不评估触发 §7.1）

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if hasMarkedText() {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        core?.normalizeCodeFontAtBoundary()
        super.insertText(string, replacementRange: replacementRange)
        guard let core, let typed = string as? String, typed.count == 1 else { return }
        switch typed {
        case " ": core.convertBlockMarkerIfNeeded()
        case "*", "~", "`", "_": core.convertInlinePairIfNeeded()
        default: break
        }
    }

    // MARK: - 键盘矩阵（§4）

    override func insertNewline(_ sender: Any?) {
        guard let core, !hasMarkedText() else {
            super.insertNewline(sender)
            return
        }
        KeyEventRouter.handleReturn(core: core, textView: self)
    }

    override func insertTab(_ sender: Any?) {
        guard let core, !hasMarkedText() else { return }
        KeyEventRouter.handleTab(shift: false, core: core, textView: self)
    }

    override func insertBacktab(_ sender: Any?) {
        guard let core, !hasMarkedText() else { return }
        KeyEventRouter.handleTab(shift: true, core: core, textView: self)
    }

    override func deleteBackward(_ sender: Any?) {
        guard let core, KeyEventRouter.handleBackspace(core: core, textView: self) else {
            super.deleteBackward(sender)
            return
        }
    }

    // MARK: - 粘贴（§8）

    override func paste(_ sender: Any?) {
        let images = PasteSanitizer.imagesOnPasteboard(NSPasteboard.general)
        if !images.isEmpty {
            for image in images {
                insertImageAttachment(image)
            }
            return
        }
        let insertionPoint = selectedRange().location
        super.paste(sender)
        if let storage = textStorage {
            // §8.1 字体归一；粘贴内容可能含多段落与列表，模型从属性重建（§11 同步边界）
            PasteSanitizer.normalizeFonts(
                in: NSRange(location: insertionPoint, length: selectedRange().location - insertionPoint),
                of: storage
            )
            core?.document.deriveFormats(from: storage)
            core?.applyAllParagraphStyles()
            core?.handleTextChanged()
        }
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

    // MARK: - 排水区点击吸附（§5.1：光标永不进入排水区）

    override func mouseDown(with event: NSEvent) {
        guard let core, let layoutManager, let textContainer, let storage = textStorage else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        var fraction: CGFloat = 0
        let charIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        core.syncFromStorage()
        let index = core.document.paragraphIndex(atLocation: min(charIndex, storage.length))
        let format = core.document.format(at: index)
        if MarkerRenderer.isInGutter(containerPoint: containerPoint, format: format, textView: self) {
            // 吸附到该段落首字符前，不进入默认选区拖拽
            setSelectedRange(NSRange(location: core.document.paragraphRange(at: index).location, length: 0))
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: - 绘制（占位文字 + 列表标记）

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let core {
            MarkerRenderer.drawMarkers(in: self, document: core.document)
        }
        drawPlaceholderIfNeeded()
    }

    private func drawPlaceholderIfNeeded() {
        guard string.isEmpty else { return }
        // §6：占位文字段落样式与正文一致
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? EditorCore.defaultFont,
            .foregroundColor: NSColor.placeholderTextColor,
            .paragraphStyle: EditorCore.baseParagraphStyle(),
        ]
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

    // MARK: - 光标区域

    /// 不调用 super：改用内缩的 I-beam 区域，把左右及底部边缘让给父视图的 resize 光标热区。
    override func resetCursorRects() {
        addCursorRect(
            NSRect(x: 6, y: 6, width: bounds.width - 12, height: bounds.height - 6),
            cursor: .iBeam
        )
    }
}

/// SwiftUI 承载壳。
struct EditorView: NSViewRepresentable {
    @ObservedObject var core: EditorCore
    var onSend: () -> Void = {}

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
        textView.font = EditorCore.defaultFont
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
        // §9 撤销重做；§6 行距；初始输入属性
        textView.allowsUndo = true
        textView.defaultParagraphStyle = EditorCore.baseParagraphStyle()
        textView.typingAttributes = EditorCore.defaultTypingAttributes

        textView.delegate = context.coordinator
        textView.onSave = onSend
        textView.core = core
        core.textView = textView
        core.document.syncFromStorage(textView.textStorage!)
        core.restoreDraft()

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        (scrollView.documentView as? EditorTextView)?.onSave = onSend
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(core: core)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let core: EditorCore
        private var observers: [NSObjectProtocol] = []

        init(core: EditorCore) {
            self.core = core
            super.init()
            // 浮窗失焦（含收起）与 App 退出时，立即落盘未写入的草稿。
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self,
                      (notification.object as? NSWindow) === self.core.textView?.window else { return }
                self.core.flushPendingPersist()
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.core.flushPendingPersist()
            })
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func textDidChange(_ notification: Notification) {
            // 内容删空后复位输入属性，避免残留的段落样式影响下一次输入。
            if let textView = notification.object as? NSTextView, textView.string.isEmpty {
                textView.typingAttributes = EditorCore.defaultTypingAttributes
            }
            core.handleTextChanged()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            core.updateTypingAttributesForCursor()
        }
    }
}
