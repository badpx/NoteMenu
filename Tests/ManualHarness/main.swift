import AppKit
import SwiftUI

// Same production view/editor, isolated draft and an inspectable local export instead of Notes.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/private/tmp/NotesMateEditorHarness")
let drafts = DraftStore(directory: root)
let model = NoteEditorModel(drafts: drafts)
let panel = NSPanel(contentRect: NSRect(x: 300, y: 200, width: 460, height: 540),
                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
panel.title = "NotesMate Editor Harness"
panel.minSize = NSSize(width: 280, height: 240)
let view = NoteEditorView(isPinned: true, onClose: { model.flushPendingPersist(); app.terminate(nil) },
    onPinChanged: { _ in }, onSaved: { panel.title = "NotesMate Editor Harness — saved locally" }, model: model,
    saveAction: { content in
        // Optional local-only latency injection for observing the saving indicator.
        if let value = try? String(contentsOf: root.appendingPathComponent("save-delay")),
           let seconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            Thread.sleep(forTimeInterval: min(30, max(0, seconds)))
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try content.bodyHTML.write(to: root.appendingPathComponent("export.html"), atomically: true, encoding: .utf8)
            return .success
        } catch { return .failed(error.localizedDescription) }
    })
panel.contentView = NSHostingView(rootView: view)
let menu = NSMenu()
let item = NSMenuItem(); menu.addItem(item)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.submenu = appMenu
app.mainMenu = menu
panel.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
DispatchQueue.main.async { panel.makeFirstResponder(model.bridge.textView) }
app.run()
