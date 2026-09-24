import AppKit
import XCTest
@testable import NotesMateEditor

final class EditorAppearanceTests: XCTestCase {
    func testTextContrastInBothAppearances() {
        func luminance(_ color: NSColor, in appearance: NSAppearance) -> CGFloat {
            var rgb: NSColor!
            appearance.performAsCurrentDrawingAppearance { rgb = color.usingColorSpace(.sRGB) }
            func linear(_ x: CGFloat) -> CGFloat { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: name)!
            for (foreground, background) in [(EditorAppearance.text, EditorAppearance.canvas),
                                            (EditorAppearance.secondary, EditorAppearance.chrome),
                                            (EditorAppearance.saveForeground, EditorAppearance.save)] {
                let a = luminance(foreground, in: appearance), b = luminance(background, in: appearance)
                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5)
            }
            // Selected controls communicate state with their icon, without a filled background.
            let a = luminance(EditorAppearance.selectedForeground, in: appearance)
            let b = luminance(EditorAppearance.chrome, in: appearance)
            XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 3)
        }
    }

    func testAppearanceSwitchPreservesDocumentAndSelection() {
        let bridge = AppKitInputBridge()
        let view = EditorTextView.make()
        bridge.attach(view)
        bridge.load(.plain("中 English\n第二行"))
        bridge.select(NSRange(location: 2, length: 7))
        let before = bridge.state
        for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            view.appearance = NSAppearance(named: name)
            view.viewDidChangeEffectiveAppearance()
            XCTAssertEqual(bridge.state, before)
            XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 7))
        }
    }
}
