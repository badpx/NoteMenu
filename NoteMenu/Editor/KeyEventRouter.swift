import AppKit

/// 键盘交互矩阵的实现（EditorSpec §4 / §3.2 / §7）：
/// IME 守卫 → 快捷键 → Enter/Tab/Backspace 路由 → 默认。
enum KeyEventRouter {
    // MARK: - 快捷键（performKeyEquivalent）

    /// 返回 true 表示事件已消费。IME 组合中（hasMarkedText）一律不拦截（§7.2）。
    static func handleKeyEquivalent(
        _ event: NSEvent,
        core: EditorCore,
        textView: EditorTextView,
        onSave: () -> Void
    ) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if modifiers == .command {
            // ⌘↩（含小键盘 Enter）保存
            if event.keyCode == 36 || event.keyCode == 76 {
                onSave()
                return true
            }
            switch key {
            // 无菜单栏（LSUIElement），⌘Z 到不了默认 Edit 菜单，这里直接接管
            case "z": textView.undoManager?.undo(); return true
            case "b": core.toggleBold(); return true
            case "i": core.toggleItalic(); return true
            case "u": core.toggleUnderline(); return true
            default: return false
            }
        } else if modifiers == [.command, .shift] {
            switch key {
            case "z": textView.undoManager?.redo(); return true
            case "x": core.toggleStrikethrough(); return true
            default: return false
            }
        }
        return false
    }

    // MARK: - Enter（§4 矩阵）

    static func handleReturn(core: EditorCore, textView: EditorTextView) {
        core.syncFromStorage()
        let index = core.cursorParagraphIndex()
        let format = core.document.format(at: index)
        let isEmptyContent = core.isParagraphContentEmpty(at: index)

        switch format.kind {
        case .body:
            core.insertNewline(withFormat: .body, typingFont: EditorCore.defaultFont)
        case .h1, .h2, .h3:
            // 标题（无论是否为空）回车 → 新正文段落（标题不延续）
            core.insertNewline(withFormat: .body, typingFont: EditorCore.defaultFont)
        case .codeBlock:
            if isEmptyContent {
                // 空行回车：退出代码块为正文段落（不插换行）
                core.degradeToBody(at: index)
            } else {
                core.insertNewline(withFormat: format, typingFont: HTMLExporter.codeFont)
            }
        case .listItem:
            if isEmptyContent {
                // 空列表项回车：层级 >1 → 提升一层（不插换行）；层级 =1 → 退出列表
                core.outdentOrExitList(at: index)
            } else {
                core.insertNewline(withFormat: format, typingFont: EditorCore.defaultFont)
            }
        }
    }

    // MARK: - Tab / Shift+Tab（仅列表项，含空项；单一实现路径 §4）

    static func handleTab(shift: Bool, core: EditorCore, textView: EditorTextView) {
        core.syncFromStorage()
        let index = core.cursorParagraphIndex()
        let format = core.document.format(at: index)
        guard format.isList else { return }  // 非列表：无操作（不跳焦点、不插制表符）
        if shift {
            core.outdentOrExitList(at: index)
        } else {
            core.indentList(at: index)
        }
    }

    // MARK: - Backspace（§4 矩阵；仅在段落首字符前生效）

    static func handleBackspace(core: EditorCore, textView: EditorTextView) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        core.syncFromStorage()
        guard textView.selectedRange().length == 0 else { return false }
        let index = core.cursorParagraphIndex()
        let contentStart = core.document.paragraphRange(at: index).location
        guard textView.selectedRange().location == contentStart else { return false }

        switch core.document.format(at: index).kind {
        case .h1, .h2, .h3, .codeBlock:
            // 降级为正文（不删字符），再按才正常退格
            core.degradeToBody(at: index)
            return true
        case .listItem:
            core.outdentOrExitList(at: index)
            return true
        case .body:
            guard index > 0 else { return true }  // 首段首：无操作
            core.mergeWithPreviousParagraph(at: index)
            return true
        }
    }
}
