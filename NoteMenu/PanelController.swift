import AppKit
import SwiftUI

private final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PanelController {
    private let panel: NSPanel
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private weak var anchorButton: NSStatusBarButton?

    /// 置顶时点击面板外部不自动收起。
    private(set) var isPinned = false

    init() {
        let panel = NotePanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow
        self.panel = panel

        let contentView = NoteEditorView(
            isPinned: false,
            onClose: { [weak self] in self?.close() },
            onPinChanged: { [weak self] pinned in self?.isPinned = pinned },
            onSaved: { [weak self] in self?.close() }
        )
        panel.contentView = NSHostingView(rootView: contentView)
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if panel.isVisible {
            close()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        anchorButton = button
        positionPanel(relativeTo: button)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusEditor()
        startEventMonitors()
    }

    func close() {
        stopEventMonitors()
        panel.orderOut(nil)
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.frame.size
        var origin = NSPoint(
            x: buttonRect.midX - panelSize.width / 2,
            y: buttonRect.minY - panelSize.height - 6
        )
        if let screen = buttonWindow.screen {
            let frame = screen.visibleFrame
            origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - panelSize.width - 8)
            origin.y = max(origin.y, frame.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }

    private func focusEditor() {
        guard let contentView = panel.contentView,
              let textView = Self.findTextView(in: contentView) else { return }
        panel.makeFirstResponder(textView)
    }

    private static func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(in: subview) { return found }
        }
        return nil
    }

    // MARK: - 点击外部收起

    private func startEventMonitors() {
        stopEventMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, !self.isPinned else { return }
            if self.isEventOnAnchorButton(at: NSEvent.mouseLocation) { return }
            self.close()
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, !self.isPinned else { return event }
            if event.window == self.panel { return event }
            if event.window != nil, event.window == self.anchorButton?.window { return event }
            self.close()
            return event
        }
    }

    private func stopEventMonitors() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func isEventOnAnchorButton(at screenPoint: NSPoint) -> Bool {
        guard let button = anchorButton, let window = button.window else { return false }
        return window.frame.contains(screenPoint)
    }
}
