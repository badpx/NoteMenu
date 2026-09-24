import AppKit

/// Shared by the SwiftUI chrome and TextKit; dynamic colors follow the window appearance.
enum EditorAppearance {
    static let headerHeight: CGFloat = 40
    static let toolbarHeight: CGFloat = 48
    static let cornerRadius: CGFloat = 14
    static let horizontalInset: CGFloat = 16

    static func color(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
    static let canvas = color(0xFFFFFF, 0x202122)
    static let chrome = color(0xFAFAF8, 0x28292A)
    static let title = color(0x202020, 0xE8E8E5)
    static let text = color(0x323232, 0xE8E8E5)
    static let secondary = color(0x70726E, 0xA9AAA7)
    static let placeholder = color(0x92938F, 0x92938F)
    static let separator = color(0xEAEAE6, 0x353638)
    static let outline = color(0xD5D5D0, 0x47484A)
    static let hover = color(0xFFF0B8, 0x494027)
    static let selectedForeground = color(0xA07800, 0xF2CC54)
    static let save = color(0xFBD32E, 0xEBC433)
    static let saveHover = color(0xE1B11C, 0xD9B22B)
    static let saveForeground = color(0x5C3E10, 0x4F390D)
    static let disabledBackground = color(0xE9E9E7, 0x353638)
    static let disabledForeground = color(0xA1A29E, 0x686A6B)
    static let code = color(0xEAEAEA, 0x2C2D2E)
}
