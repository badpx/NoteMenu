import AppKit
import XCTest
@testable import NoteMenuEditor

final class EditorPersistenceTests: XCTestCase {
    func store() -> DraftStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NoteMenuTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return DraftStore(directory: directory)
    }

    func testEmptyFormattedDraftAndLatestGeneration_D01_D04() throws {
        let store = store()
        for i in 0..<20 { store.persist(.plain("obsolete \(i)")) }
        let last = EditorDocument(paragraphs: [Paragraph(kind: .list(.ordered, 3))])
        store.persist(last); store.flush()
        XCTAssertNil(store.lastError)
        let restored = try XCTUnwrap(store.restore())
        XCTAssertEqual(restored.paragraphs, last.paragraphs)
        XCTAssertFalse(restored.canSend)
        XCTAssertFalse(restored.isPristine)
        store.persist(.plain("old")); store.persist(EditorDocument()); store.flush()
        XCTAssertNil(try store.restore())
    }

    func testLegacyMigrationAndNoResurrection_D05() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let source = NSAttributedString(string: "legacy", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        let data = try XCTUnwrap(source.rtfd(from: NSRange(location: 0, length: source.length), documentAttributes: [:]))
        try data.write(to: store.legacyURL)
        let document = try XCTUnwrap(store.restore())
        XCTAssertEqual(document.text, "legacy")
        XCTAssertTrue(document.paragraphs[0].runs[0].style.marks.contains(.bold))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.legacyURL.path))
        store.persist(EditorDocument()); store.flush()
        XCTAssertNil(try store.restore())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyURL.path))
    }

    func testDamagedDraftPreservedAndWriteFailure_D06() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let corrupted = Data("damaged".utf8)
        try corrupted.write(to: store.url)
        XCTAssertThrowsError(try store.restore())
        XCTAssertEqual(try Data(contentsOf: store.url), corrupted)
        store.persist(.plain("new")); store.flush()
        let recovered = try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("draft-recovery-") }
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(try Data(contentsOf: recovered[0]), corrupted)
        XCTAssertEqual(try store.restore()?.text, "new")
        let badPath = store.directory.appendingPathComponent("file")
        try Data().write(to: badPath)
        let failing = DraftStore(directory: badPath)
        failing.persist(.plain("still here")); failing.flush()
        XCTAssertNotNil(failing.lastError)
    }

    func testSaveSuccessFailureAndRevisionGuard_U08_E10() throws {
        let store = store()
        let model = NoteEditorModel(drafts: store, restore: false)
        model.bridge.load(.plain("original"))
        let failure = model.save { _ in .unauthorized("denied") }
        XCTAssertEqual(failure, .unauthorized("denied"))
        XCTAssertEqual(model.bridge.document.text, "original")
        let success = model.save { content in
            XCTAssertEqual(content.bodyHTML, "<div>original</div>")
            return .success
        }
        XCTAssertEqual(success, .success)
        XCTAssertTrue(model.bridge.document.isPristine)
        XCTAssertFalse(model.bridge.history.manager.canUndo)
        model.bridge.load(.plain("snapshot"))
        model.save { _ in model.bridge.load(.plain("new input")); return .success }
        XCTAssertEqual(model.bridge.document.text, "new input")
        model.flushPendingPersist()
        XCTAssertEqual(try store.restore()?.text, "new input")
    }

    func testModelFormattingSchedulesDraftWithoutTyping_D01_D02() throws {
        let store = store()
        let model = NoteEditorModel(drafts: store, restore: false)
        model.setBlock(.heading(2))
        model.flushPendingPersist()
        XCTAssertEqual(try store.restore()?.paragraphs[0].kind, .heading(2))
        model.clear(); model.flushPendingPersist()
        XCTAssertNil(try store.restore())
    }

    func testImageDraftAndMissingAsset_P08_D06_D07() throws {
        let store = store()
        let image = NSImage(size: NSSize(width: 30, height: 80))
        image.lockFocus(); NSColor.green.setFill(); NSRect(x: 0, y: 0, width: 30, height: 80).fill(); image.unlockFocus()
        let document = ClipboardCodec.imageFragment([image])
        store.persist(document); store.flush()
        let restored = try XCTUnwrap(store.restore())
        XCTAssertEqual(restored.assets, document.assets)
        XCTAssertEqual(restored.assetOrder, document.assetOrder)
        var invalid = document; invalid.assets = [:]
        XCTAssertThrowsError(try invalid.validated())
        store.persist(EditorDocument()); store.flush()
        XCTAssertNil(try store.restore())
    }

    func testCompositionDraftContainsOnlyCommittedState_I04() throws {
        let store = store()
        let model = NoteEditorModel(drafts: store, restore: false)
        let view = EditorTextView.make(); model.bridge.attach(view)
        view.insertText("committed", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        model.flushPendingPersist()
        XCTAssertEqual(try store.restore()?.text, "committed")
        view.insertText("中文", replacementRange: view.markedRange())
        model.flushPendingPersist()
        XCTAssertEqual(try store.restore()?.text, "committed中文")
    }

    func testEmptyInlineIntentSurvivesRestart_D02() throws {
        let store = store()
        let model = NoteEditorModel(drafts: store, restore: false)
        model.toggleBold(); model.flushPendingPersist()
        let restored = NoteEditorModel(drafts: store)
        XCTAssertTrue(restored.isEmpty)
        XCTAssertTrue(restored.bridge.state.session.insertionStyle.marks.contains(.bold))
        let view = EditorTextView.make(); restored.bridge.attach(view)
        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(restored.bridge.document.paragraphs[0].runs[0].style.marks.contains(.bold))
    }

    func testLegacyRTFDPackageWithImage_D05() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 20, height: 30))
        image.lockFocus(); NSColor.purple.setFill(); NSRect(x: 0, y: 0, width: 20, height: 30).fill(); image.unlockFocus()
        let rich = NSMutableAttributedString(string: "legacy image", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        rich.append(TextKitRenderer.render(ClipboardCodec.imageFragment([image]), exchange: true))
        let wrapper = try XCTUnwrap(rich.rtfdFileWrapper(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]))
        try wrapper.write(to: store.legacyURL, options: .atomic, originalContentsURL: nil)
        let restored = try XCTUnwrap(store.restore())
        XCTAssertEqual(restored.text, "legacy image\u{FFFC}")
        XCTAssertTrue(restored.paragraphs[0].runs[0].style.marks.contains(.bold))
        XCTAssertEqual(restored.assetOrder.count, 1)
        XCTAssertNotNil(NSImage(data: try XCTUnwrap(restored.assets[restored.assetOrder[0]]).data))
        XCTAssertEqual(try store.restore()?.assets, restored.assets)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.legacyURL.path))
    }
}
