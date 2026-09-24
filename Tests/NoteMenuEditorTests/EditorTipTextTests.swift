import AppKit
import XCTest
@testable import NoteMenuEditor

final class EditorTipTextTests: XCTestCase {
    func testAllLanguagesUseKeycapsAndKeepChordsTogether() {
        let cases: [(EditorTip, String, Int)] = [
            (.heading, "Start a line with # and a space to create a heading.", 1),
            (.indent, "Press Tab to indent and ⇧+Tab to outdent.", 2),
            (.codeExit, "Press ↓ on the last line of a code block to return to body text.", 1),
            (.selectAll, "Press ⌘+A repeatedly to select the entire note.", 1)
        ]
        for language in EditorLanguage.supported {
            for (tip, key, count) in cases {
                let text = EditorTipText.attributed(tip, message: EditorLanguage.text(key, languages: [language]))
                var attachments: [NSTextAttachment] = []
                text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                    if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
                }
                XCTAssertEqual(attachments.count, count, "\(language): \(key)")
                XCTAssertTrue(attachments.allSatisfy { $0.bounds.height == 18 })
                if tip == .selectAll { XCTAssertEqual(attachments.first?.bounds.width, TipKeycap.size(["⌘", "A"]).width) }
                if tip == .indent { XCTAssertEqual(attachments.last?.bounds.width, TipKeycap.size(["⇧", "Tab"]).width) }
                XCTAssertLessThanOrEqual(EditorTipText.height(text, width: 240), 90, language)
            }
        }
    }
    func testOrdinaryNoticesDoNotInterpretKeyboardLikeText() {
        let message = "Tab ⇧+Tab ⌘+A ↓ #"
        let text = EditorTipText.attributed(.information(id: "test", message: message))
        XCTAssertEqual(text.string, message)
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            XCTAssertNil(value)
        }
    }
}
