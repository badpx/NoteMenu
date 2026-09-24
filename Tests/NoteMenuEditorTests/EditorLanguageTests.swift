import AppKit
import XCTest
@testable import NoteMenuEditor

final class EditorLanguageTests: XCTestCase {
    func testRegionsScriptsAliasesAndUnsupportedPrimaryLanguage() {
        let cases = ["zh-CN": "zh-Hans", "zh_SG": "zh-Hans", "zh-TW": "zh-Hant",
                     "zh-HK": "zh-Hant", "zh-MO": "zh-Hant", "zh-Hans-HK": "zh-Hans",
                     "zh-Hant-CN": "zh-Hant", "en-GB": "en", "pt-BR": "pt", "pt-PT": "pt",
                     "fil-PH": "fil", "tl-PH": "fil", "in-ID": "id", "id-ID": "id", "ja-JP": "ja"]
        for (input, expected) in cases { XCTAssertEqual(EditorLanguage.language(for: [input]), expected, input) }
        for language in EditorLanguage.supported {
            XCTAssertEqual(EditorLanguage.language(for: [language]), language)
        }
        for languages in [[], ["ru-RU"], ["ar", "zh-Hans"], ["xx", "de"], [""]] {
            XCTAssertEqual(EditorLanguage.language(for: languages), "en")
            XCTAssertEqual(EditorLanguage.text("Body", languages: languages), "Body")
        }
        XCTAssertEqual(EditorLanguage.text("Body", languages: ["fr-FR"]), "Corps")
        XCTAssertEqual(EditorLanguage.text("New Note", languages: ["zh-Hant"]), "新增筆記")
    }

    func testEveryCatalogIsCompleteAndPreservesParameters() throws {
        let english = EditorLanguage.catalog(for: "en")
        XCTAssertEqual(EditorLanguage.supported.count, 15)
        XCTAssertGreaterThan(english.count, 80)
        let regex = try NSRegularExpression(pattern: "\\{[0-9]+\\}")
        func parameters(_ text: String) -> [String] {
            regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
                .map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        for language in EditorLanguage.supported {
            let catalog = EditorLanguage.catalog(for: language)
            XCTAssertEqual(Set(catalog.keys), Set(english.keys), language)
            for (key, value) in catalog {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(language): \(key)")
                XCTAssertEqual(parameters(value), parameters(key), "\(language): \(key)")
                XCTAssertFalse(value.contains("NoteMenu"), "\(language): \(key)")
                XCTAssertEqual(EditorLanguage.text(key, languages: [language]), value)
            }
        }
    }

    func testFormattingTreatsUserContentLiterally() {
        XCTAssertEqual(EditorLanguage.format("{0} (error: {1})", "{1} %@ 100%", "42", languages: ["en"]),
                       "{1} %@ 100% (error: 42)")
        XCTAssertEqual(EditorLanguage.format("Save folder: {0}", "\"旅行\" {0}", languages: ["en"]),
                       "Save folder: \"旅行\" {0}")
        XCTAssertTrue(EditorLanguage.format("Hello, welcome to {0}.\nCapture ideas and save to Apple Notes.",
                                           AppIdentity.productName, languages: ["zh-Hans"]).contains("你好，欢迎使用NotesMate，\n"))
        XCTAssertEqual(EditorLanguage.text("Future untranslated key", languages: ["ja"]), "Future untranslated key")
    }

    func testAllLocalizedTipsFitMinimumWindowWithoutChangingWidth() throws {
        let keys = ["Start a line with # and a space to create a heading.", "Press Tab to indent and ⇧+Tab to outdent.",
                    "Press ↓ on the last line of a code block to return to body text.",
                    "Press ⌘+A repeatedly to select the entire note.",
                    "Hello, welcome to {0}.\nCapture ideas and save to Apple Notes."]
        for language in EditorLanguage.supported {
            for key in keys {
                let message = EditorLanguage.format(key, AppIdentity.productName, languages: [language])
                let tip = EditorTip.information(id: "localization", message: message)
                let small = try XCTUnwrap(EditorTipContext.frame(for: tip, in: CGSize(width: 360, height: 250)), language)
                let wide = try XCTUnwrap(EditorTipContext.frame(for: tip, in: CGSize(width: 720, height: 250)), language)
                XCTAssertEqual(small.width, 300)
                XCTAssertEqual(small.size, wide.size)
                XCTAssertGreaterThanOrEqual(small.height, 40)
                XCTAssertLessThanOrEqual(small.height, 100, "\(language): \(message)")
            }
        }
    }
}
