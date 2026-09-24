import AppKit
import SwiftUI

/// Within-window blending samples the editor, not the desktop behind the panel.
private struct TipMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct TipSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if !reduceTransparency { TipMaterial() }
                    Color(nsColor: EditorAppearance.tipBackground)
                        .opacity(reduceTransparency ? 1 : (scheme == .dark ? 0.70 : 0.65))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: EditorAppearance.tipBorder), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.16 : 0.08), radius: 5, y: 2)
    }
}

struct EditorTipOverlay: View {
    @ObservedObject var tips: EditorTipsController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            if let tip = tips.visible, tip != .save,
               let rect = EditorTipContext.frame(for: tip, in: geometry.size) {
                ZStack(alignment: .trailing) {
                    HStack(spacing: 6) {
                        Image(systemName: tip.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(nsColor: EditorAppearance.selectedForeground))
                            .frame(width: 12, alignment: .leading)
                            .padding(.trailing, 4)
                            .accessibilityHidden(true)
                        TipMessageView(tip: tip)
                            .frame(maxWidth: .infinity)
                            .frame(height: rect.height - 16)
                        Color.clear.frame(width: EditorTipContext.dismissSize, height: EditorTipContext.dismissSize)
                    }
                    .foregroundStyle(Color(nsColor: EditorAppearance.tipText))
                    .padding(.horizontal, EditorTipContext.horizontalPadding)
                    .frame(width: rect.width, height: rect.height)
                    .modifier(TipSurface())
                    .allowsHitTesting(false)
                    Button { tips.dismissCurrent() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 6, weight: .medium))
                            .frame(width: EditorTipContext.dismissSize, height: EditorTipContext.dismissSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(TipDismissStyle())
                    .accessibilityLabel(EditorLanguage.text("Dismiss Tip"))
                    .padding(.trailing, EditorTipContext.horizontalPadding)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: tips.visible)
    }
}

private struct TipDismissStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TipDismissLabel(content: configuration.label, pressed: configuration.isPressed)
    }
    private struct TipDismissLabel<Content: View>: View {
        let content: Content
        let pressed: Bool
        @State private var hovered = false
        var body: some View {
            content.foregroundStyle(Color(nsColor: hovered || pressed ? EditorAppearance.selectedForeground : EditorAppearance.secondary))
                .background(Color(nsColor: hovered || pressed ? EditorAppearance.hover : EditorAppearance.chrome),
                            in: Circle())
                .onHover { hovered = $0 }
        }
    }
}

struct SaveShortcutTip: View {
    @ObservedObject var tips: EditorTipsController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if tips.visible == .save {
                HStack(spacing: 6) {
                    Text(EditorTip.save.message)
                    Image(nsImage: TipKeycap.image(["⌘", "↩"]))
                        .accessibilityHidden(true)
                }
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: EditorAppearance.tipText))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .modifier(TipSurface())
                .fixedSize()
                .accessibilityLabel(EditorLanguage.text("Save to Notes, Command Return"))
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: tips.visible)
    }
}

/// Draw and measure the same attributed string so inline keycaps wrap with the
/// localized sentence, without affecting the editor's layout or mouse handling.
private struct TipMessageView: NSViewRepresentable {
    let tip: EditorTip
    func makeNSView(context: Context) -> MessageView { MessageView() }
    func updateNSView(_ view: MessageView, context: Context) {
        view.tip = tip
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.staticText)
        view.setAccessibilityLabel(tip.message)
        view.needsDisplay = true
    }
    final class MessageView: NSView {
        var tip: EditorTip = .save
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
        override func draw(_ dirtyRect: NSRect) {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                let text = EditorTipText.attributed(tip)
                let height = EditorTipText.height(text, width: bounds.width)
                text.draw(with: NSRect(x: 0, y: max(0, (bounds.height - height) / 2),
                                       width: bounds.width, height: height),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
        }
    }
}

/// Observes only this window; never monitors other applications or changes editor focus.
struct TipWindowObserver: NSViewRepresentable {
    let tips: EditorTipsController
    let bridge: AppKitInputBridge
    func makeNSView(context: Context) -> ObserverView { ObserverView(tips: tips, bridge: bridge) }
    func updateNSView(_ view: ObserverView, context: Context) {}
    final class ObserverView: NSView {
        let tips: EditorTipsController
        let bridge: AppKitInputBridge
        private var observers: [NSObjectProtocol] = []
        private var monitor: Any?
        init(tips: EditorTipsController, bridge: AppKitInputBridge) {
            self.tips = tips; self.bridge = bridge
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else { tips.endSession(); return }
            let center = NotificationCenter.default
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.tips.deactivate()
                })
            }
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.tips.activate()
            })
            observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                self?.tips.activity()
            })
            observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                self?.tips.menuTracking(true)
            })
            observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                self?.tips.menuTracking(false)
            })
            observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.tips.preferencesChanged()
            })
            // The document view can be attached after this background view enters its window.
            DispatchQueue.main.async { [weak self] in self?.observeScroll() }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp, .leftMouseDragged, .scrollWheel]) { [weak self, weak window] event in
                guard let self, event.window === window else { return event }
                if event.type == .leftMouseUp || event.type == .rightMouseUp {
                    // A format change or selection may have queued a tip while the
                    // mouse was held. Retry after AppKit finishes the release.
                    DispatchQueue.main.async { [weak self] in self?.tips.editorChanged() }
                    return event
                }
                if event.type == .keyDown, event.keyCode == 53, !self.bridge.isComposing,
                   window?.attachedSheet == nil, self.tips.escape() { return nil }
                if event.type == .leftMouseDown, self.isDismissButton(event.locationInWindow) { return event }
                if event.type == .leftMouseDown || event.type == .rightMouseDown {
                    self.bridge.hooks.emit(.pointerPress, context: self.bridge.hookContext)
                }
                self.tips.editingActivity()
                return event
            }
            if window.isKeyWindow { tips.activate() }
        }
        private func observeScroll() {
            guard let clip = bridge.textView?.enclosingScrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                self?.tips.editingActivity(clearStatus: false)
            })
        }
        private func isDismissButton(_ point: NSPoint) -> Bool {
            guard let tip = tips.visible, tip != .save, let scroll = bridge.textView?.enclosingScrollView,
                  let rect = EditorTipContext.frame(for: tip, in: scroll) else { return false }
            return NSBezierPath(ovalIn: EditorTipContext.dismissFrame(in: rect))
                .contains(scroll.convert(point, from: nil))
        }
        private func removeObservers() {
            observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
        deinit { removeObservers() }
    }
}
