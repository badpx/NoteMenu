import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = PanelController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            button.image = NSImage(
                systemSymbolName: "square.and.pencil",
                accessibilityDescription: "NoteMenu"
            )?.withSymbolConfiguration(config)
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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

        let launchItem = NSMenuItem(
            title: "开机自启动",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 NoteMenu",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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
            alert.messageText = "无法更新开机自启动设置"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
