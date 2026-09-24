import AppKit
import SwiftUI

// Render the production view in isolation: no real draft, Notes request, or user defaults writes.
let args = CommandLine.arguments
let language = args.count > 1 ? args[1] : "en"
let dark = args.count > 2 && args[2] == "dark"
let width = args.count > 3 ? Double(args[3])! : 380
UserDefaults.standard.setVolatileDomain(["AppleLanguages": [language]], forName: UserDefaults.argumentDomain)
precondition(EditorLanguage.text("Body") == EditorLanguage.text("Body", languages: [language]), "Preview must use the requested language")
let app = NSApplication.shared
let verifyTips = args.contains("--verify-tips")
app.setActivationPolicy(.prohibited)
let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
app.appearance = appearance
let output = URL(fileURLWithPath: "build/design-preview")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sampleFolder = NotesFolder(id: "preview", name: language.hasPrefix("zh") ? "会议纪要" : "Meetings", accountName: "Preview")
var windows: [NSWindow] = []
var models: [NoteEditorModel] = []
let tipsMode = args.contains("--tips")
for state in tipsMode ? ["heading-tip", "indent-tip", "code-tip", "save-tip", "select-all-tip", "information-tip"] : ["empty", "editing"] {
    let editing = state != "empty"
    let suite = "NoteMenu.preview.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let tips = EditorTipsController(history: EditorTipHistory(defaults: defaults), timing: .init(hover: 0.01))
    let model = NoteEditorModel(drafts: DraftStore(directory: output.appendingPathComponent(UUID().uuidString)), restore: false, tips: tips)
    if editing {
        func copy(_ zh: String, _ en: String) -> String { language.hasPrefix("zh") ? zh : en }
        model.bridge.load(EditorDocument(paragraphs: [
            Paragraph(kind: .heading(1), runs: [InlineRun(text: copy("让想法及时落地", "Give ideas a place"))]),
            Paragraph(runs: [InlineRun(text: copy("把零散的灵感，留给下一次思考。", "Save a thought. Come back to it later."))]),
            Paragraph(kind: .list(.unordered, 1), runs: [InlineRun(text: copy("随手记录，不打断当前工作", "Capture ideas without losing focus"))]),
            Paragraph(kind: .list(.unordered, 1), runs: [InlineRun(text: copy("整理好，再存进系统备忘录", "Save them directly to Apple Notes"))])
        ]))
        model.bridge.select(NSRange(location: model.bridge.document.length, length: 0))
    }
    if state == "code-tip" {
        model.bridge.load(EditorDocument(paragraphs: [
            Paragraph(kind: .heading(1), runs: [InlineRun(text: (language.hasPrefix("zh") ? "一段小代码" : "A little code"))]),
            Paragraph(kind: .codeLine, runs: [InlineRun(text: "func greet() {")]),
            Paragraph(kind: .codeLine, runs: [InlineRun(text: "    print(\"Hello\")")]),
            Paragraph(kind: .codeLine, runs: [InlineRun(text: "}")])
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
    if verifyTips { window.makeFirstResponder(model.bridge.textView) }
    var beforeState = model.bridge.state
    let textFrame = model.bridge.textView!.frame
    let scrollBounds = model.bridge.textView!.enclosingScrollView!.contentView.bounds
    if tipsMode {
        // Offscreen windows cannot become key. Bypass only that presentation gate for snapshots.
        tips.canPresent = { tip in verifyTips ? EditorTipContext.geometryAllows(tip, in: model.bridge) : true }
        tips.endSession()
        defaults.removePersistentDomain(forName: suite)
        if state != "indent-tip" { tips.learned(.indent) } // Keep the preview focused on the requested state.
        tips.activate()
        if state == "code-tip" {
            // Opening on an existing code line no longer synthesizes entry.
            // Move from the heading into code to exercise a real transition.
            model.bridge.select(NSRange(location: 0, length: 0))
            model.bridge.select(NSRange(location: model.bridge.document.length, length: 0))
            beforeState = model.bridge.state
        }
        if state == "heading-tip" { tips.showFeature(.heading) }
        if state == "indent-tip" { tips.showFeature(.indent) }
        if state == "save-tip" { tips.saveHover(true) }
        if state == "select-all-tip" {
            let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
            precondition(model.bridge.textView!.performKeyEquivalent(with: key))
            beforeState = model.bridge.state
        }
        if state == "information-tip" {
            tips.showInformation(id: "preview", message: EditorLanguage.format("Hello, welcome to {0}.\nCapture ideas and save to Apple Notes.", AppIdentity.productName))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.18))
        hosting.layoutSubtreeIfNeeded()
        let expected: EditorTip = state == "heading-tip" ? .heading : state == "indent-tip" ? .indent : state == "save-tip" ? .save : state == "select-all-tip" ? .selectAll : .codeExit
        precondition(state == "information-tip" ? tips.visible?.id == "info.preview" : tips.visible == expected)
        precondition(model.bridge.state == beforeState, "Tips must not change the note or selection")
        precondition(model.bridge.textView!.frame == textFrame, "Tips must not reflow the editor")
        precondition(model.bridge.textView!.enclosingScrollView!.contentView.bounds == scrollBounds, "Tips must not scroll the editor")
    }
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("No bitmap") }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let file = "\(language)-\(dark ? "dark" : "light")-\(state)-\(Int(width)).png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(file))
    print(file)
    if verifyTips && state == "code-tip" {
        let editor = model.bridge.textView!
        let scroll = editor.enclosingScrollView!
        precondition(EditorTipContext.geometryAllows(.codeExit, in: model.bridge))
        let rect = EditorTipContext.frame(for: .codeExit, in: scroll)!
        let textPoint = hosting.superview!.convert(NSPoint(x: rect.midX, y: rect.midY), from: scroll)
        let hit = hosting.hitTest(textPoint)
        precondition(hit === editor, "Tip body must pass clicks to editor, got \(String(describing: hit))")
        let closeRect = EditorTipContext.dismissFrame(in: rect)
        let closePoint = hosting.superview!.convert(NSPoint(x: closeRect.midX, y: closeRect.midY), from: scroll)
        precondition(hosting.hitTest(closePoint) !== editor, "Dismiss button must remain interactive")
        let caretIndex = model.bridge.document.paragraphs[0].length / 2
        model.bridge.select(NSRange(location: caretIndex, length: 0))
        precondition(EditorTipContext.geometryAllows(.codeExit, in: model.bridge), "Entering a format must permit a top overlay even near the caret")
        precondition(tips.visible == .codeExit, "Selection changes must preserve an already visible teaching tip")
        print("PASS: production view geometry, selection-compatible overlay, click-through, dismiss hit target, unchanged note/layout")
    }
}
