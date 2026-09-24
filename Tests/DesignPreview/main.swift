import AppKit
import SwiftUI

// Render the production view in isolation: no real draft, Notes request, or user defaults writes.
let args = CommandLine.arguments
let language = args.count > 1 ? args[1] : "en"
let dark = args.count > 2 && args[2] == "dark"
let width = args.count > 3 ? Double(args[3])! : 380
UserDefaults.standard.setVolatileDomain(["AppleLanguages": [language]], forName: UserDefaults.argumentDomain)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
app.appearance = appearance
let output = URL(fileURLWithPath: "build/design-preview")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sampleFolder = NotesFolder(id: "preview", name: language.hasPrefix("zh") ? "会议纪要" : "Meetings", accountName: "Preview")
var windows: [NSWindow] = []
var models: [NoteEditorModel] = []
for editing in [false, true] {
    let model = NoteEditorModel(drafts: DraftStore(directory: output.appendingPathComponent(UUID().uuidString)), restore: false)
    if editing {
        func copy(_ zh: String, _ en: String) -> String { EditorLanguage.text(zh, en) }
        model.bridge.load(EditorDocument(paragraphs: [
            Paragraph(kind: .heading(1), runs: [InlineRun(text: copy("让想法及时落地", "Give ideas a place"))]),
            Paragraph(),
            Paragraph(runs: [InlineRun(text: copy("把零散的灵感，留给下一次思考。", "Save a thought. Come back to it later."))]),
            Paragraph(),
            Paragraph(kind: .list(.unordered, 1), runs: [InlineRun(text: copy("随手记录，不打断当前工作", "Capture ideas without losing focus"))]),
            Paragraph(kind: .list(.unordered, 1), runs: [InlineRun(text: copy("整理好，再存进系统备忘录", "Save them directly to Apple Notes"))])
        ]))
        model.bridge.select(NSRange(location: model.bridge.document.length, length: 0))
    }
    let root = NoteEditorView(isPinned: false, onClose: {}, onPinChanged: { _ in }, onSaved: {}, model: model,
                              saveAction: { _ in .success }, initialFolder: sampleFolder, folderLoader: { [sampleFolder] })
    let hosting = NSHostingView(rootView: root)
    let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: width, height: 410),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = appearance
    window.backgroundColor = .clear
    window.isOpaque = false
    window.contentView = hosting
    window.orderFront(nil)
    windows.append(window); models.append(model)
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    hosting.layoutSubtreeIfNeeded()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("No bitmap") }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let file = "\(language)-\(dark ? "dark" : "light")-\(editing ? "editing" : "empty")-\(Int(width)).png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(file))
    print(file)
}
