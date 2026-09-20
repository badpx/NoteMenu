import AppKit
import XCTest
@testable import NoteMenuEditor

final class AsyncSaveTests: XCTestCase {
    func testBackgroundAppleScriptInterpreter() {
        let model = NoteEditorModel(drafts: store(), restore: false)
        model.bridge.load(.plain("snapshot"))
        let done = expectation(description: "interpreter")
        model.saveAsync(using: { _ in
            do {
                XCTAssertEqual(try NotesSaver.runScript("return \"background-ready\""), "background-ready")
                return .success
            } catch { XCTFail(error.localizedDescription); return .failed(error.localizedDescription) }
        }, completion: { result in
            XCTAssertEqual(result, .success)
            XCTAssertTrue(model.isEmpty)
            XCTAssertFalse(model.isSaving)
            done.fulfill()
        })
        wait(for: [done], timeout: 5)
    }
    func store() -> DraftStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NoteMenuAsyncTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return DraftStore(directory: directory)
    }
    func testAsyncSaveStaysResponsiveRejectsDuplicatesAndRestoresFailure() {
        let model = NoteEditorModel(drafts: store(), restore: false)
        model.bridge.load(.plain("keep me"))
        let started = expectation(description: "background writer")
        let finished = expectation(description: "main completion")
        let release = DispatchSemaphore(value: 0)
        model.saveAsync(using: { _ in
            XCTAssertFalse(Thread.isMainThread)
            started.fulfill()
            _ = release.wait(timeout: .now() + 3)
            return .failed("test")
        }, completion: { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertFalse(model.isSaving)
            XCTAssertEqual(result, .failed("test"))
            XCTAssertEqual(model.bridge.document.text, "keep me")
            finished.fulfill()
        })
        XCTAssertTrue(model.isSaving)
        model.saveAsync(using: { _ in XCTFail("duplicate save"); return .success }, completion: { _ in XCTFail("duplicate completion") })
        wait(for: [started], timeout: 2)
        release.signal()
        wait(for: [finished], timeout: 3)
    }

    func testAsyncSavePreservesEditsMadeAfterSnapshot() {
        let model = NoteEditorModel(drafts: store(), restore: false)
        model.bridge.load(.plain("snapshot"))
        let done = expectation(description: "done")
        model.saveAsync(using: { content in
            XCTAssertEqual(content.bodyHTML, "<div>snapshot</div>")
            return .success
        }, completion: { _ in
            XCTAssertFalse(model.isSaving)
            XCTAssertEqual(model.bridge.document.text, "new draft")
            done.fulfill()
        })
        model.bridge.load(.plain("new draft"))
        wait(for: [done], timeout: 3)
    }

}
