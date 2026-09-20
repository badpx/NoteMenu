import AppKit
import XCTest
@testable import NoteMenuEditor

final class NotesSaverTests: XCTestCase {
    func image() -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.red, atX: x, y: y) } }
        let image = NSImage(size: NSSize(width: 2, height: 2)); image.addRepresentation(bitmap); return image
    }
    func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func content() -> NotesSaver.NoteContent {
        .init(bodyHTML: "<div>A\(HTMLExporter.imagePlaceholder(0))B\(HTMLExporter.imagePlaceholder(1))C</div>", images: [image(), image()])
    }
    func testExporterPreservesRepeatedImageOccurrencesAndEscapesUserText() throws {
        let id = UUID()
        let doc = EditorDocument(paragraphs: [Paragraph(runs: [InlineRun(text: "A"), .image(id), InlineRun(text: "B"), .image(id), InlineRun(text: "C<!--NoteMenuImage:0-->")])])
        let export = HTMLExporter.export(doc)
        XCTAssertEqual(export.assetIDs, [id, id])
        let html = try NotesSaver.resolveHTML(export.bodyHTML, imagePaths: ["/tmp/a & \"1.png", "/tmp/b.png"])
        XCTAssertTrue(html.final.contains("A<img"))
        XCTAssertTrue(html.final.contains(">B<img"))
        XCTAssertTrue(html.final.contains(">C&lt;!--NoteMenuImage:0--&gt;"))
        XCTAssertFalse(html.final.contains("<!--NoteMenuImage:"))
        XCTAssertTrue(html.final.contains("%22"))
        XCTAssertThrowsError(try NotesSaver.resolveHTML(export.bodyHTML, imagePaths: ["/tmp/a.png"]))
    }
    func testSuccessfulSaveVerifiesEveryOccurrenceBeforeCleanup() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var calls: [String] = []
        let result = NotesSaver.save(content(), execute: { script in
            calls.append(script)
            if script.contains("return id of newNote") { return "test-note" }
            if script.contains("save attachment") {
                let directory = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)[0]
                for i in 0..<2 {
                    try FileManager.default.copyItem(at: directory.appendingPathComponent("image-\(i).png"),
                                                     to: directory.appendingPathComponent("verify-\(i).png"))
                }
            }
            return ""
        }, temporaryRoot: root)
        XCTAssertEqual(result, .success)
        XCTAssertEqual(calls.count, 3)
        XCTAssertFalse(calls[0].contains("<!--NoteMenuImage:"))
        XCTAssertTrue(calls[1].range(of: "make new attachment")!.lowerBound < calls[1].range(of: "set body")!.lowerBound)
        XCTAssertFalse(calls.joined().contains("activate"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testCorruptAttachmentRollsBackAndDoesNotReportSuccess() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var rolledBack = false
        let result = NotesSaver.save(content(), execute: { script in
            if script.contains("return id of newNote") { return "test-note" }
            if script.contains("save attachment") {
                let dir = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)[0]
                for i in 0..<2 { try Data("corrupt".utf8).write(to: dir.appendingPathComponent("verify-\(i).png")) }
            }
            if script.contains("delete note id") { rolledBack = true }
            return ""
        }, temporaryRoot: root, verificationAttempts: 1)
        guard case .failed = result else { return XCTFail("Must fail") }
        XCTAssertTrue(rolledBack)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testRollbackFailureRetainsSourceImages() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let result = NotesSaver.save(content(), execute: { script in
            if script.contains("return id of newNote") { return "test-note" }
            throw NotesSaver.ScriptError(number: -10000, message: "injected failure")
        }, temporaryRoot: root, verificationAttempts: 1)
        guard case .failed(let message) = result else { return XCTFail("Must fail") }
        XCTAssertTrue(message.contains("避免重试产生重复笔记"))
        let dir = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)[0]
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("image-0.png").path))
    }
    func testMissingImageStopsBeforeAppleScript() {
        var called = false
        let result = NotesSaver.save(.init(bodyHTML: HTMLExporter.imagePlaceholder(0), images: []), execute: { _ in called = true; return "" })
        guard case .failed = result else { return XCTFail("Must fail") }
        XCTAssertFalse(called)
    }

    func testPlainTextRemainsOneBackgroundCall() {
        var calls = 0
        let result = NotesSaver.save(.init(bodyHTML: "<div>正文</div>", images: []), execute: { script in
            calls += 1
            XCTAssertFalse(script.contains("attachment"))
            return "test-note"
        })
        XCTAssertEqual(result, .success)
        XCTAssertEqual(calls, 1)
    }

    func testAttachmentReadinessCanRetry() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0
        let result = NotesSaver.save(content(), execute: { script in
            if script.contains("return id of newNote") { return "test-note" }
            if script.contains("save attachment") {
                checks += 1
                if checks == 1 { throw NotesSaver.ScriptError(number: -10000, message: "not ready") }
                let dir = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)[0]
                for i in 0..<2 {
                    try FileManager.default.copyItem(at: dir.appendingPathComponent("image-\(i).png"),
                                                     to: dir.appendingPathComponent("verify-\(i).png"))
                }
            }
            return ""
        }, temporaryRoot: root, verificationAttempts: 2)
        XCTAssertEqual(result, .success)
        XCTAssertEqual(checks, 2)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}
