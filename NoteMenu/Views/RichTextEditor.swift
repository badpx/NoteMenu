import AppKit
import SwiftUI

struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var model: NoteEditorModel
    var onSend: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let view = EditorTextView.make()
        scroll.documentView = view
        model.bridge.attach(view)
        model.bridge.onSave = onSend
        context.coordinator.observe(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        model.bridge.onSave = onSend
        (scroll.documentView as? NSTextView)?.isEditable = !model.isSaving
        (scroll.documentView as? NSTextView)?.isSelectable = !model.isSaving
    }
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.model.flushPendingPersist()
        coordinator.model.bridge.onSave = nil
    }

    final class Coordinator {
        let model: NoteEditorModel
        var observers: [NSObjectProtocol] = []
        init(model: NoteEditorModel) { self.model = model }
        func observe(_ view: NSTextView) {
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self, weak view] note in
                if (note.object as? NSWindow) === view?.window { self?.model.flushPendingPersist() }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                self?.model.flushPendingPersist()
            })
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
