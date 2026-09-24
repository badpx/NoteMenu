import AppKit
import Combine

enum EditorTip: Equatable, Hashable {
    case heading, indent, codeExit, selectAll, save
    case information(id: String, message: String)

    var id: String {
        switch self {
        case .heading: return "format.heading"
        case .indent: return "list.indent"
        case .codeExit: return "code.exit"
        case .selectAll: return "selection.expand"
        case .save: return "save.shortcut"
        case .information(let id, _): return "info." + id
        }
    }
    var isFeature: Bool {
        switch self { case .information, .save: return false; default: return true }
    }
    var icon: String { isFeature ? "lightbulb" : "info.circle" }
    var message: String {
        switch self {
        case .heading: return EditorLanguage.text("Start a line with # and a space to create a heading.")
        case .indent: return EditorLanguage.text("Press Tab to indent and ⇧+Tab to outdent.")
        case .codeExit: return EditorLanguage.text("Press ↓ on the last line of a code block to return to body text.")
        case .selectAll: return EditorLanguage.text("Press ⌘+A repeatedly to select the entire note.")
        case .save: return EditorLanguage.text("Save to Notes")
        case .information(_, let message): return message
        }
    }
}

final class EditorTipHistory {
    static let enabledKey = "editorTips.enabled"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var enabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
    // V3 separates actual learning from the old 'close means learned' records.
    func isLearned(_ tip: EditorTip) -> Bool { defaults.bool(forKey: "tips.v3.learned.\(tip.id)") }
    func canShow(_ tip: EditorTip) -> Bool { !tip.isFeature || enabled && !isLearned(tip) }
    func learn(_ tip: EditorTip) {
        guard tip.isFeature else { return }
        defaults.set(true, forKey: "tips.v3.learned.\(tip.id)")
    }
}

/// Main-thread presentation only. FIFO notices share one slot; events never modify
/// the current notice's deadline. Generation guards make cancelled callbacks harmless.
final class EditorTipsController: ObservableObject {
    struct Timing {
        var hover: TimeInterval = 0.15
        var duration: TimeInterval = 2
    }
    private struct Request { let tip: EditorTip; let duration: TimeInterval }
    @Published private(set) var visible: EditorTip?
    var onSessionBegan: (() -> Void)?
    var canPresent: (EditorTip) -> Bool = { _ in false }
    var canSave: () -> Bool = { false }
    let activityEvents = PassthroughSubject<Void, Never>()
    let history: EditorTipHistory
    private let timing: Timing
    private let enqueue: (TimeInterval, DispatchWorkItem) -> Void
    private var pending: DispatchWorkItem?
    private var expiry: DispatchWorkItem?
    private var generation = 0
    private var queue: [Request] = []
    // The panel owns this controller for the application lifetime. Never reset on
    // window reopen, draft creation, or preference changes; never persist to disk.
    private var shownThisLaunch: Set<String> = []
    private var sessionActive = false
    private var active = false
    private var saveHovered = false
    private var saveFocused = false
    private var saveVisitConsumed = false
    private var blocked = false
    private var menuTrackingDepth = 0
    private var isBlocked: Bool { blocked || menuTrackingDepth > 0 }

    init(history: EditorTipHistory = EditorTipHistory(), timing: Timing = Timing(),
         enqueue: @escaping (TimeInterval, DispatchWorkItem) -> Void = { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) }) {
        self.history = history; self.timing = timing; self.enqueue = enqueue
    }
    func beginSession(initialMessage: String? = nil) {
        guard !sessionActive else { return }
        sessionActive = true
        saveHovered = false; saveFocused = false; saveVisitConsumed = false
        // Initial notices precede teaching requests emitted by draft creation.
        if let initialMessage { showInformation(id: "session.initial", message: initialMessage) }
        onSessionBegan?()
    }
    func endSession() {
        sessionActive = false; active = false; menuTrackingDepth = 0
        queue.removeAll(); cancelPresentation()
    }
    func activate() { beginSession(); active = true; drain() }
    func deactivate() { active = false; cancelPresentation() }
    func setBlocked(_ value: Bool) {
        blocked = value
        if value { cancelPresentation() } else { drain() }
    }
    func menuTracking(_ began: Bool) {
        menuTrackingDepth = max(0, menuTrackingDepth + (began ? 1 : -1))
        if began { cancelPresentation() } else { drain() }
    }
    func activity(clearStatus: Bool = true) {
        queue.removeAll(); cancelPresentation()
        if clearStatus { activityEvents.send() }
    }
    func editingActivity(clearStatus: Bool = true) {
        if visible == .save || saveHovered || saveFocused { cancelPresentation() }
        if clearStatus { activityEvents.send() }
    }
    func editorChanged() { drain() }

    func showFeature(_ tip: EditorTip) {
        guard tip.isFeature else { return }
        request(tip, duration: timing.duration)
    }
    func showInformation(id: String = UUID().uuidString, message: String, duration: TimeInterval? = nil) {
        request(.information(id: id, message: message), duration: duration ?? timing.duration)
    }
    private func request(_ tip: EditorTip, duration: TimeInterval) {
        guard sessionActive, history.canShow(tip), !tip.isFeature || !shownThisLaunch.contains(tip.id),
              visible?.id != tip.id, !queue.contains(where: { $0.tip.id == tip.id }) else { return }
        queue.append(Request(tip: tip, duration: duration.isFinite && duration > 0 ? duration : timing.duration))
        drain()
    }
    func removePending(_ tip: EditorTip) { queue.removeAll { $0.tip.id == tip.id } }
    func learned(_ tip: EditorTip) { history.learn(tip); removePending(tip) }
    func preferencesChanged() {
        queue.removeAll { !history.canShow($0.tip) }
        if visible?.isFeature == true, !history.enabled { cancelPresentation() }
        drain()
    }
    func dismissCurrent() { cancelPresentation(); drain() }
    @discardableResult func escape() -> Bool {
        guard visible != nil else { return false }
        dismissCurrent(); return true
    }

    private func drain() {
        guard active, sessionActive, !isBlocked, visible == nil, pending == nil,
              !saveHovered, !saveFocused, !queue.isEmpty else { return }
        // Next main-loop turn: format/menu/selection processing must finish first.
        schedule(after: 0) { [weak self] in
            guard let self, self.active, self.sessionActive, !self.isBlocked, self.visible == nil else { return }
            self.queue.removeAll { !self.history.canShow($0.tip) || $0.tip.isFeature && self.shownThisLaunch.contains($0.tip.id) }
            guard let next = self.queue.first, self.canPresent(next.tip) else { return }
            self.queue.removeFirst()
            if next.tip.isFeature { self.shownThisLaunch.insert(next.tip.id) }
            self.present(next)
        }
    }
    func saveHover(_ value: Bool) { saveHovered = value; updateSaveVisit() }
    func saveFocus(_ value: Bool) { saveFocused = value; updateSaveVisit() }
    private func updateSaveVisit() {
        guard saveHovered || saveFocused else {
            saveVisitConsumed = false
            if visible == .save || pending != nil { cancelPresentation() }
            drain(); return
        }
        guard !saveVisitConsumed else { return }
        saveVisitConsumed = true
        cancelPresentation()
        guard active, !isBlocked, canSave() else { return }
        schedule(after: timing.hover) { [weak self] in
            guard let self, self.active, !self.isBlocked, self.saveHovered || self.saveFocused, self.canSave() else { return }
            self.present(Request(tip: .save, duration: self.timing.duration))
        }
    }
    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expected else { return }
            self.pending = nil; action()
        }
        pending = work; enqueue(delay, work)
    }
    private func present(_ request: Request) {
        generation += 1
        visible = request.tip
        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expected else { return }
            self.visible = nil; self.expiry = nil
            self.drain()
        }
        expiry = work; enqueue(request.duration, work)
    }
    private func cancelPresentation() {
        generation += 1
        pending?.cancel(); pending = nil
        expiry?.cancel(); expiry = nil
        if visible != nil { visible = nil }
    }
    deinit { pending?.cancel(); expiry?.cancel() }
}

enum EditorTipContext {
    static let horizontalPadding: CGFloat = 10
    static let dismissSize: CGFloat = 12
    static func dismissFrame(in rect: CGRect) -> CGRect {
        CGRect(x: rect.maxX - horizontalPadding - dismissSize, y: rect.midY - dismissSize / 2,
               width: dismissSize, height: dismissSize)
    }
    static func frame(for tip: EditorTip, in size: CGSize) -> CGRect? {
        let width = min(300, size.width - 32)
        guard width >= 180 else { return nil }
        let textWidth = width - 2 * horizontalPadding - 28 - dismissSize // icon, 10pt/6pt gaps and dismiss target
        let height = max(24, EditorTipText.height(EditorTipText.attributed(tip), width: textWidth)) + 16
        guard size.height >= height + 20 else { return nil }
        return CGRect(x: (size.width - width) / 2, y: 8, width: width, height: height)
    }

    static func frame(for tip: EditorTip, in scroll: NSScrollView) -> CGRect? {
        guard var rect = frame(for: tip, in: scroll.bounds.size) else { return nil }
        if !scroll.isFlipped { rect.origin.y = scroll.bounds.height - rect.maxY }
        return rect.offsetBy(dx: scroll.bounds.minX, dy: scroll.bounds.minY)
    }

    static func canPresent(_ tip: EditorTip, in bridge: AppKitInputBridge) -> Bool {
        guard !bridge.isComposing, NSEvent.pressedMouseButtons == 0,
              let view = bridge.textView, let window = view.window,
              window.isKeyWindow, window.isVisible, window.attachedSheet == nil,
              view.isEditable, let scroll = view.enclosingScrollView else { return false }
        return frame(for: tip, in: scroll) != nil
    }
    static func geometryAllows(_ tip: EditorTip, in bridge: AppKitInputBridge) -> Bool {
        guard let scroll = bridge.textView?.enclosingScrollView else { return false }
        return frame(for: tip, in: scroll) != nil
    }
}
