import AppKit

/// A key is scoped to its dispatch, not the last key ever pressed. Mouse/menu actions
/// therefore cannot accidentally inherit an earlier Down-arrow learning gesture.
struct EditorKey: Equatable {
    var code: UInt16
    var modifiers: NSEvent.ModifierFlags = []
    var isRepeat = false
    var characters: String?
    init(code: UInt16, modifiers: NSEvent.ModifierFlags = [], isRepeat: Bool = false, characters: String? = nil) {
        self.code = code
        self.modifiers = modifiers.intersection([.command, .control, .option, .shift])
        self.isRepeat = isRepeat
        self.characters = characters?.lowercased()
    }
    init(_ event: NSEvent) { self.init(code: event.keyCode, modifiers: event.modifierFlags, isRepeat: event.isARepeat, characters: event.charactersIgnoringModifiers) }
    var isSelectAll: Bool { (characters == "a" || characters == nil && code == 0) && modifiers == .command }
    var isDown: Bool { code == 125 && modifiers.isEmpty }
    var isTab: Bool { code == 48 && (modifiers.isEmpty || modifiers == .shift) }
}

struct EditorHookContext {
    let key: EditorKey?
    let format: BlockKind
    let selection: NSRange
    let revision: UInt64
    let isComposing: Bool
    let isPristine: Bool
    /// One-based completed selection stage, zero before the first select-all.
    let selectionStage: Int
    let selectionStageCount: Int
}

enum EditorHook {
    case sessionStarted, draftCreated, keyPress, afterKeyPress, keyRelease, beforeInput, afterInput, selectionChanged, pointerPress
    case enterFormat(BlockKind), leaveFormat(BlockKind)
    case markdownShortcutApplied(MarkdownTriggerEngine.Plan)
}

/// Read-only notifications. Subscribers may observe, but must not mutate the document
/// synchronously from a hook. Each subscription has an explicit removal token.
final class EditorHooks {
    private var observers: [UUID: (EditorHook, EditorHookContext) -> Void] = [:]
    @discardableResult func observe(_ action: @escaping (EditorHook, EditorHookContext) -> Void) -> UUID {
        let id = UUID(); observers[id] = action; return id
    }
    func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    func emit(_ hook: EditorHook, context: EditorHookContext) {
        for observer in Array(observers.values) { observer(hook, context) }
    }
}

/// Feature-specific teaching lives here; the editor only publishes operation facts.
final class EditorFeatureTips {
    private weak var tips: EditorTipsController?
    init(tips: EditorTipsController) { self.tips = tips }

    func handle(_ hook: EditorHook, context: EditorHookContext) {
        switch hook {
        case .draftCreated:
            tips?.showFeature(.heading)
        case .markdownShortcutApplied(let plan):
            if case .block(_, .heading) = plan { tips?.learned(.heading) }
        case .enterFormat(let format):
            if format.isCode { tips?.showFeature(.codeExit) }
            if let list = format.list, list.depth < ListResolver.maxDepth { tips?.showFeature(.indent) }
        case .leaveFormat(let format):
            if format.isCode {
                tips?.removePending(.codeExit)
                if context.key?.isDown == true, !context.isComposing { tips?.learned(.codeExit) }
            }
            if format.list != nil {
                tips?.removePending(.indent)
                if context.key?.isTab == true, !context.isComposing { tips?.learned(.indent) }
            }
        case .keyPress:
            if context.key?.isSelectAll != true { tips?.removePending(.selectAll) }
        case .afterKeyPress:
            // Read the editor's completed selection result; no separate key streak
            // or previous-selection state is needed in the teaching layer.
            guard !context.isComposing, let key = context.key, key.isSelectAll,
                  !key.isRepeat, context.selectionStage > 0 else { return }
            if context.selectionStage > 1 {
                tips?.learned(.selectAll)
            } else if context.selectionStage < context.selectionStageCount {
                tips?.showFeature(.selectAll)
            }
        case .pointerPress:
            tips?.removePending(.selectAll)
        case .selectionChanged:
            if context.key?.isSelectAll != true {
                tips?.removePending(.selectAll)
            }
        case .sessionStarted, .keyRelease, .beforeInput, .afterInput:
            break
        }
    }
}
