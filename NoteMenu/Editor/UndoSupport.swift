import AppKit

/// Undo/Redo（EditorSpec §9）：快照式注册。一次自动转换/一次格式操作为一个 undo 组
/// （与同事件的键入自动合并）；撤销后文档模型、光标、列表标记三者同步还原
/// （快照含模型格式数组）。undo 闭包内再次注册即 redo。
enum UndoSupport {
    struct Snapshot {
        let text: NSAttributedString
        let formats: [ParagraphFormat]
        let selection: NSRange
    }

    static func capture(storage: NSTextStorage, document: EditorDocument, textView: NSTextView) -> Snapshot {
        Snapshot(
            text: (storage.copy() as? NSAttributedString) ?? NSAttributedString(),
            formats: (0..<document.paragraphCount).map { document.format(at: $0) },
            selection: textView.selectedRange()
        )
    }

    static func registerSnapshot(
        storage: NSTextStorage,
        document: EditorDocument,
        textView: NSTextView,
        onRestore: (() -> Void)? = nil
    ) {
        guard let undoManager = textView.undoManager else { return }
        let snapshot = capture(storage: storage, document: document, textView: textView)
        undoManager.registerUndo(withTarget: textView) { target in
            guard let storage = target.textStorage else { return }
            registerSnapshot(storage: storage, document: document, textView: target, onRestore: onRestore)
            storage.setAttributedString(snapshot.text)
            document.restoreFormats(snapshot.formats)
            target.setSelectedRange(
                NSRange(location: min(snapshot.selection.location, snapshot.text.length), length: 0)
            )
            target.needsDisplay = true
            onRestore?()
        }
    }
}
