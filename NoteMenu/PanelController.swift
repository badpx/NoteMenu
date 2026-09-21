import AppKit
import SwiftUI

/// 边缘 resize 热区划分（窗口坐标，y 轴向上），与 NoteEditorView 的 SwiftUI 拖动手柄几何一致。
/// 光标热区与拖拽命中共用同一套几何，保证「看到什么光标就能拖什么」。
private func edgeCursorRects(in bounds: NSRect) -> [(rect: NSRect, cursor: NSCursor)] {
    let edge: CGFloat = 6
    let corner: CGFloat = 18
    return [
        (NSRect(x: 0, y: 0, width: corner, height: corner), .neswDiagonalResize),
        (NSRect(x: bounds.width - corner, y: 0, width: corner, height: corner), .nwseDiagonalResize),
        (NSRect(x: corner, y: 0, width: bounds.width - corner * 2, height: edge), .resizeUpDown),
        (NSRect(x: 0, y: corner, width: edge, height: bounds.height - corner), .resizeLeftRight),
        (NSRect(x: bounds.width - edge, y: corner, width: edge, height: bounds.height - corner), .resizeLeftRight),
    ]
}

private func findTextView(in view: NSView) -> NSTextView? {
    if let textView = view as? NSTextView { return textView }
    for subview in view.subviews {
        if let found = findTextView(in: subview) { return found }
    }
    return nil
}

private final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    private weak var editorTextView: NSTextView?

    private func editorClipView() -> NSView? {
        if editorTextView == nil, let contentView {
            editorTextView = findTextView(in: contentView)
        }
        return editorTextView?.enclosingScrollView?.contentView
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, attachedSheet == nil, let contentView {
            // Match the 36pt custom title bar; leave side resize handles and Pin/Close untouched.
            let dragRect = NSRect(x: 6, y: contentView.bounds.height - 36,
                                  width: max(0, contentView.bounds.width - 78), height: 36)
            if dragRect.contains(event.locationInWindow) {
                performDrag(with: event)
                return
            }
        }
        super.sendEvent(event)
        // NSTextView 会在事件分发中把自己的 I-beam 盖过 cursorRect 的结果，
        // 因此在 mouseMoved/cursorUpdate 分发结束后统一按鼠标位置裁定光标：
        // 边缘热区用 resize 光标，文本区用 I-beam，其余用箭头。拖动中不动光标。
        guard event.type == .mouseMoved || event.type == .cursorUpdate,
              NSEvent.pressedMouseButtons == 0,
              let contentView else { return }
        let point = event.locationInWindow
        if let hit = edgeCursorRects(in: contentView.bounds).first(where: { $0.rect.contains(point) }) {
            hit.cursor.set()
            return
        }
        // 文本区判断用几何包含而非 hitTest：SwiftUI 布局更新期间 hitTest 结果不稳定。
        if let clipView = editorClipView(),
           clipView.bounds.contains(clipView.convert(point, from: nil)) {
            NSCursor.iBeam.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

/// 浮窗内容容器：负责边缘热区的 resize 光标。
/// SwiftUI 的 onContinuousHover + NSCursor.push 会被 AppKit 的 cursorUpdate 机制覆盖，
/// 因此光标用 NSView 的 cursorRect 实现（另由 NotePanel.sendEvent 兜底强制）。
private final class PanelContentView: NSView {
    override func resetCursorRects() {
        for entry in edgeCursorRects(in: bounds) {
            addCursorRect(entry.rect, cursor: entry.cursor)
        }
    }
}

private extension NSCursor {
    /// 右下角（↘↖）斜向调整尺寸光标：macOS 15+ 用系统原生，旧系统回退到自绘。
    static let nwseDiagonalResize: NSCursor = {
        if #available(macOS 15, *) {
            return NSCursor.frameResize(position: .bottomRight, directions: .all)
        }
        return NSCursor.diagonalResize(flip: false)
    }()

    /// 左下角（↙↗）斜向调整尺寸光标。
    static let neswDiagonalResize: NSCursor = {
        if #available(macOS 15, *) {
            return NSCursor.frameResize(position: .bottomLeft, directions: .all)
        }
        return NSCursor.diagonalResize(flip: true)
    }()

    /// macOS 13/14 没有公开的斜向 resize 光标（frameResize 系列要 macOS 15），自行绘制：
    /// 一条对角线加两端 L 形箭头，白描边保证深浅背景都可见。
    private static func diagonalResize(flip: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: flip ? 16 - x : x, y: y)
            }
            // 坐标系 y 轴向上：NW 端在 (4, 12)，SE 端在 (12, 4)。
            let outline = NSBezierPath()
            let body = NSBezierPath()
            for path in [outline, body] {
                path.move(to: point(4, 12))
                path.line(to: point(12, 4))
                path.move(to: point(4, 8))
                path.line(to: point(4, 12))
                path.line(to: point(8, 12))
                path.move(to: point(12, 8))
                path.line(to: point(12, 4))
                path.line(to: point(8, 4))
            }
            outline.lineWidth = 3.5
            outline.lineCapStyle = .round
            outline.lineJoinStyle = .round
            NSColor.white.setStroke()
            outline.stroke()
            body.lineWidth = 1.5
            body.lineCapStyle = .round
            body.lineJoinStyle = .round
            NSColor.black.setStroke()
            body.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
    }
}

/// 浮窗边缘拖动手柄：由 NoteEditorView 的边缘热区驱动，调整浮窗尺寸并回调持久化。
/// 只支持左、右、下三个方向，顶部保留给标题栏拖动。
final class PanelResizeHandler {
    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let bottom = Edges(rawValue: 1 << 2)
    }

    static let minSize = NSSize(width: 280, height: 240)

    private weak var panel: NSPanel?
    private var startFrame: NSRect?
    private var startMouse: NSPoint?

    var onResizeEnd: ((NSSize) -> Void)?

    init(panel: NSPanel) {
        self.panel = panel
    }

    /// 拖动手势进行中调用。位移必须用屏幕坐标（NSEvent.mouseLocation）计算：
    /// 面板随拖动实时变形，手势所在视图坐标系随之下移，用其 translation 会产生正反馈（增量减半）。
    func resize(edges: Edges) {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if startFrame == nil {
            startFrame = panel.frame
            startMouse = mouse
        }
        guard let startFrame, let startMouse else { return }
        let delta = CGSize(width: mouse.x - startMouse.x, height: mouse.y - startMouse.y)
        var frame = startFrame
        if edges.contains(.right) {
            frame.size.width = max(Self.minSize.width, startFrame.width + delta.width)
        }
        if edges.contains(.left) {
            let width = max(Self.minSize.width, startFrame.width - delta.width)
            frame.origin.x = startFrame.maxX - width
            frame.size.width = width
        }
        if edges.contains(.bottom) {
            // 屏幕坐标 y 轴向上：向下拖动时 delta.height 为负，高度增加。
            let height = max(Self.minSize.height, startFrame.height - delta.height)
            frame.origin.y = startFrame.maxY - height
            frame.size.height = height
        }
        panel.setFrame(frame, display: true)
    }

    func endResize() {
        guard let panel, startFrame != nil else { return }
        startFrame = nil
        startMouse = nil
        onResizeEnd?(panel.frame.size)
    }
}

final class PanelController {
    private let panel: NSPanel
    private let resizeHandler: PanelResizeHandler
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var moveObserver: NSObjectProtocol?
    private weak var anchorButton: NSStatusBarButton?

    private static let panelSizeKey = "panelSize"
    private static let panelOriginKey = "panelOrigin"
    private static let defaultPanelSize = NSSize(width: 340, height: 400)

    /// 置顶时点击面板外部不自动收起。
    private(set) var isPinned = false

    init() {
        let storedSize = UserDefaults.standard.string(forKey: Self.panelSizeKey).map(NSSizeFromString)
        let size = storedSize.flatMap { size in
            size.width >= PanelResizeHandler.minSize.width && size.height >= PanelResizeHandler.minSize.height
                ? size : nil
        } ?? Self.defaultPanelSize
        let panel = NotePanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        panel.isMovable = true
        panel.animationBehavior = .utilityWindow
        self.panel = panel

        let resizeHandler = PanelResizeHandler(panel: panel)
        resizeHandler.onResizeEnd = { [weak panel] size in
            UserDefaults.standard.set(NSStringFromSize(size), forKey: Self.panelSizeKey)
            if UserDefaults.standard.string(forKey: Self.panelOriginKey) != nil, let panel {
                UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.panelOriginKey)
            }
        }
        self.resizeHandler = resizeHandler

        let contentView = NoteEditorView(
            isPinned: false,
            resizeHandler: resizeHandler,
            onClose: { [weak self] in self?.close() },
            onPinChanged: { [weak self] pinned in self?.isPinned = pinned },
            onSaved: { [weak self] in
                guard let self, self.panel.isKeyWindow else { return }
                self.focusEditor()
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        let container = PanelContentView(frame: NSRect(origin: .zero, size: size))
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container
        // performDrag can return before the final window frame is applied. Persist actual move
        // notifications instead of assuming its return marks the end of the drag.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            guard let panel, panel.isVisible else { return }
            UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.panelOriginKey)
        }
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        stopEventMonitors()
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
        // Also capture the final position before hiding, including a just-completed drag.
        if panel.isVisible {
            UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.panelOriginKey)
        }
        stopEventMonitors()
        panel.orderOut(nil)
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        if let stored = UserDefaults.standard.string(forKey: Self.panelOriginKey) {
            let origin = NSPointFromString(stored)
            if origin.x.isFinite, origin.y.isFinite {
                let savedFrame = NSRect(origin: origin, size: panel.frame.size)
                let screen = NSScreen.screens.filter { $0.visibleFrame.intersects(savedFrame) }.max {
                    let a = $0.visibleFrame.intersection(savedFrame)
                    let b = $1.visibleFrame.intersection(savedFrame)
                    return a.width * a.height < b.width * b.height
                } ?? buttonWindow.screen ?? NSScreen.main
                if let screen {
                    // Keep the title bar reachable after a monitor is unplugged or its resolution changes.
                    let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
                    let size = NSSize(width: min(panel.frame.width, visible.width),
                                      height: min(panel.frame.height, visible.height))
                    let adjusted = NSPoint(x: min(max(origin.x, visible.minX), visible.maxX - size.width),
                                           y: min(max(origin.y, visible.minY), visible.maxY - size.height))
                    panel.setFrame(NSRect(origin: adjusted, size: size), display: false)
                    return
                }
            }
        }
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
              let textView = findTextView(in: contentView) else { return }
        panel.makeFirstResponder(textView)
    }

    // MARK: - 点击外部收起

    private func startEventMonitors() {
        stopEventMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, !self.isPinned, self.panel.attachedSheet == nil else { return }
            if self.isEventOnAnchorButton(at: NSEvent.mouseLocation) { return }
            self.close()
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, !self.isPinned, self.panel.attachedSheet == nil else { return event }
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
