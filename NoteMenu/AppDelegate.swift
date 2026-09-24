import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!
    private var hotKeys: [EventHotKeyRef] = []
    private var hotKeyHandler: EventHandlerRef?
    private static let newNoteHotKeyID = EventHotKeyID(signature: 0x4E4D4E55, id: 1)
    private static let openNotesHotKeyID = EventHotKeyID(signature: 0x4E4D4E55, id: 2)
    private static let didShowFirstLaunchEditorKey = "didShowFirstLaunchEditor"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = PanelController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let icon = NSImage(named: "StatusIcon")
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = true
            icon?.accessibilityDescription = "NoteMenu"
            button.image = icon
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        registerHotKeys()
        // Wait until the status item is attached before anchoring the first window.
        // Persist independently of window/draft state so later launches stay quiet.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !UserDefaults.standard.bool(forKey: Self.didShowFirstLaunchEditorKey),
                  let button = self.statusItem.button else { return }
            let productName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NoteMenu"
            let welcome = EditorLanguage.text(
                "你好，欢迎使用\(productName)，\n你可随时记录想法并保存至系统备忘录。",
                "Welcome to \(productName).\nCapture ideas and save to Apple Notes.")
            self.panelController.show(relativeTo: button, welcomeMessage: welcome)
            UserDefaults.standard.set(true, forKey: Self.didShowFirstLaunchEditorKey)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    private func registerHotKeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr,
                  identifier.signature == AppDelegate.newNoteHotKeyID.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            switch identifier.id {
            case AppDelegate.newNoteHotKeyID.id:
                delegate.toggleNoteWindow()
            case AppDelegate.openNotesHotKeyID.id:
                DispatchQueue.main.async { [weak delegate] in delegate?.openNotes(nil) }
            default:
                return OSStatus(eventNotHandledErr)
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)

        var failures: [String] = []
        for (keyCode, identifier, label) in [
            (kVK_ANSI_N, Self.newNoteHotKeyID, EditorLanguage.text("新建笔记 ⌃⌘N", "New Note ⌃⌘N")),
            (kVK_ANSI_O, Self.openNotesHotKeyID, EditorLanguage.text("打开备忘录 ⌃⌘O", "Open Notes ⌃⌘O")),
        ] {
            var hotKey: EventHotKeyRef?
            let status = handlerStatus == noErr
                ? RegisterEventHotKey(UInt32(keyCode), UInt32(controlKey | cmdKey), identifier,
                                      GetApplicationEventTarget(), 0, &hotKey)
                : handlerStatus
            if status == noErr, let hotKey {
                hotKeys.append(hotKey)
            } else {
                failures.append(EditorLanguage.text("\(label)（错误码：\(status)）", "\(label) (error: \(status))"))
            }
        }
        // 一个快捷键注册失败时，仍保留另一个可用的快捷键。
        if hotKeys.isEmpty, let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
            self.hotKeyHandler = nil
        }
        guard !failures.isEmpty else { return }
        let message = failures.joined(separator: "\n")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = EditorLanguage.text("无法注册快捷键", "Unable to Register Shortcuts")
            alert.informativeText = EditorLanguage.text("以下快捷键可能已被其他应用占用：\n\(message)\n仍可通过菜单栏图标的右键菜单执行对应操作。", "These shortcuts may be in use by another app:\n\(message)\nYou can still use the menu bar icon’s context menu.")
            alert.addButton(withTitle: EditorLanguage.text("好", "OK"))
            alert.runModal()
        }
    }

    private func toggleNoteWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            self.panelController.toggle(relativeTo: button)
        }
    }

    @objc private func newNote(_ sender: Any?) {
        // 等菜单关闭后再激活面板，避免菜单跟踪结束时夺走输入焦点。
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            self.panelController.show(relativeTo: button)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            panelController.toggle(relativeTo: sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let newNoteItem = NSMenuItem(
            title: EditorLanguage.text("新建笔记", "New Note"),
            action: #selector(newNote(_:)),
            keyEquivalent: "n"
        )
        newNoteItem.keyEquivalentModifierMask = [.control, .command]
        newNoteItem.target = self
        menu.addItem(newNoteItem)

        let openNotesItem = NSMenuItem(
            title: EditorLanguage.text("打开备忘录", "Open Notes"),
            action: #selector(openNotes(_:)),
            keyEquivalent: "o"
        )
        openNotesItem.keyEquivalentModifierMask = [.control, .command]
        openNotesItem.target = self
        menu.addItem(openNotesItem)
        menu.addItem(.separator())

        let tipsItem = NSMenuItem(title: EditorLanguage.text("显示编辑小贴士", "Show Editing Tips"),
                                 action: #selector(toggleEditorTips(_:)), keyEquivalent: "")
        tipsItem.target = self
        tipsItem.state = EditorTipHistory().enabled ? .on : .off
        menu.addItem(tipsItem)
        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: EditorLanguage.text("开机自启动", "Launch at Login"),
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        let quitItem = NSMenuItem(
            title: EditorLanguage.text("退出 NoteMenu", "Quit NoteMenu"),
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openNotes(_ sender: Any?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") else {
            showOpenNotesError(EditorLanguage.text("未找到系统备忘录应用。", "Apple Notes could not be found."))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async { self?.showOpenNotesError(error.localizedDescription) }
        }
    }

    private func showOpenNotesError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = EditorLanguage.text("无法打开备忘录", "Unable to Open Notes")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: EditorLanguage.text("好", "OK"))
        alert.runModal()
    }

    @objc private func toggleEditorTips(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!EditorTipHistory().enabled, forKey: EditorTipHistory.enabledKey)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = EditorLanguage.text("无法更新开机自启动设置", "Unable to Update Launch at Login")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: EditorLanguage.text("好", "OK"))
            alert.runModal()
        }
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
