import AppKit

final class UndoCoordinator {
    let manager = UndoManager()
    var restore: ((EditorSnapshot) -> Void)?
    var snapshot: (() -> EditorSnapshot)?

    func prepareNativeEvent() {
        guard manager.groupingLevel == 0 else { return }
        // A semantic transaction may have closed the event's automatic group. Re-open it
        // before AppKit registers another edit in that SAME event; do not split each key.
        manager.beginUndoGrouping()
        if manager.groupingLevel == 2 { manager.endUndoGrouping() }
    }

    func sealTyping(in view: NSTextView?) {
        view?.breakUndoCoalescing()
        // This manager is editor-owned. Native AppKit calls must have returned before sealing.
        if manager.groupingLevel == 1 { manager.endUndoGrouping() }
        assert(manager.groupingLevel == 0, "Unexpected nested editor undo transaction")
    }

    func register(_ before: EditorSnapshot, name: String, view: NSTextView?) {
        guard !manager.isUndoing, !manager.isRedoing else { return }
        sealTyping(in: view)
        let byEvent = manager.groupsByEvent
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        registerRestore(before)
        manager.setActionName(name)
        manager.endUndoGrouping()
        manager.groupsByEvent = byEvent
    }

    private func registerRestore(_ state: EditorSnapshot) {
        manager.registerUndo(withTarget: self) { target in
            guard let inverse = target.snapshot?() else { return }
            target.registerRestore(inverse)
            target.restore?(state)
        }
    }

    func withoutRegistration(_ body: () -> Void) {
        manager.disableUndoRegistration()
        defer { manager.enableUndoRegistration() }
        body()
    }
}
