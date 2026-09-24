// Opt-in integration probe: writes only to the explicitly supplied test folder.
import AppKit

@main
struct InlineSaveProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("Usage: InlineSaveProbe test-folder image1.png image2.png")
        }
        let folder = CommandLine.arguments[1]
        let a = UUID(), b = UUID()
        let data1 = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let data2 = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
        let assets = [a: ImageAsset(data: data1, width: 220, height: 64), b: ImageAsset(data: data2, width: 220, height: 64)]
        let cases = [
            EditorDocument(paragraphs: [
                Paragraph(kind: .heading(1), runs: [InlineRun(text: "NotesMate 正式保存验收")]),
                Paragraph(runs: [InlineRun(text: "A 前文"), .image(a), InlineRun(text: "B 同段后文")]),
                Paragraph(kind: .list(.unordered, 1), runs: [InlineRun(text: "列表红图之后"), .image(b)]),
                Paragraph(kind: .list(.unordered, 2), runs: [InlineRun(text: "第二级列表")]),
                Paragraph(runs: [InlineRun(text: "C 重复红图之前"), .image(a), InlineRun(text: "D 最后文字")])
            ], assets: assets),
            EditorDocument(paragraphs: [Paragraph(runs: [.image(b)])], assets: assets)
        ]
        for document in cases {
            let model = NoteEditorModel(drafts: DraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("NotesMate-InlineSaveProbe-Drafts")), restore: false)
            model.bridge.load(document)
            let content = model.exportContent()!
            var noteID = ""
            let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let result = NotesSaver.save(content, execute: { script in
                let scoped = script.replacingOccurrences(of: "at default folder of default account", with: "at folder \(NotesSaver.quote(folder)) of default account")
                let output = try NotesSaver.runScript(scoped)
                if script.contains("return id of newNote") { noteID = output }
                return output
            })
            print("result=\(result), frontmostUnchanged=\(before == NSWorkspace.shared.frontmostApplication?.bundleIdentifier), note=\(noteID)")
            guard result == .success else { exit(1) }
            // The saver has now removed its temporary directory. Export again independently.
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotesMate-post-save-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let files = content.images.indices.map { root.appendingPathComponent("\($0).png") }
            _ = try NotesSaver.runScript(NotesSaver.verificationScript(noteID: noteID, exports: files))
            for (i, file) in files.enumerated() {
                guard try Data(contentsOf: file) == NotesSaver.pngData(for: content.images[i]) else { fatalError("Post-cleanup image mismatch") }
            }
            print("post-cleanup verified \(files.count) images in occurrence order")
        }
    }
}
