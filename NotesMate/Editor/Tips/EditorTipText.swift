import AppKit

/// Only known shortcuts in feature tips become keycaps. Ordinary notices and user
/// content remain literal, even when they contain a matching keyboard symbol.
enum EditorTipText {
    static func shortcuts(in tip: EditorTip) -> [String: [String]] {
        switch tip {
        case .heading: return ["#": ["#"]]
        case .indent: return ["Tab": ["Tab"], "⇧+Tab": ["⇧", "Tab"]]
        case .codeExit: return ["↓": ["↓"]]
        case .selectAll: return ["⌘+A": ["⌘", "A"]]
        default: return [:]
        }
    }

    static func attributed(_ tip: EditorTip, message: String? = nil) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let font = NSFont.systemFont(ofSize: 12)
        let text = message ?? tip.message
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: EditorAppearance.tipText, .paragraphStyle: paragraph
        ])
        let shortcuts = shortcuts(in: tip)
        guard !shortcuts.isEmpty else { return result }
        // Longest match first keeps Shift+Tab together rather than replacing its Tab suffix.
        let pattern = shortcuts.keys.sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let regex = try! NSRegularExpression(pattern: pattern)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).reversed() {
            let labels = shortcuts[(text as NSString).substring(with: match.range)]!
            let attachment = NSTextAttachment()
            attachment.image = TipKeycap.image(labels)
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - TipKeycap.height) / 2,
                                       width: TipKeycap.size(labels).width, height: TipKeycap.height)
            let replacement = NSMutableAttributedString(attachment: attachment)
            replacement.addAttributes([.font: font, .paragraphStyle: paragraph], range: NSRange(location: 0, length: 1))
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result
    }

    static func height(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(with: NSSize(width: width, height: 10_000),
                              options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }
}

/// Shared by inline feature shortcuts and the save shortcut bubble.
/// A chord is one image attachment so wrapping can never split its keys.
enum TipKeycap {
    static let height: CGFloat = 18
    static let gap: CGFloat = 3
    static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    static func width(_ label: String) -> CGFloat {
        label.count == 1 ? 18 : max(18, ceil((label as NSString).size(withAttributes: [.font: font]).width) + 8)
    }
    static func size(_ labels: [String]) -> NSSize {
        NSSize(width: labels.reduce(0) { $0 + width($1) } + CGFloat(max(0, labels.count - 1)) * gap, height: height)
    }
    static func image(_ labels: [String]) -> NSImage {
        let image = NSImage(size: size(labels), flipped: false) { _ in
            var x: CGFloat = 0
            for label in labels {
                let width = TipKeycap.width(label)
                let rect = NSRect(x: x, y: 0, width: width, height: height)
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 3, yRadius: 3)
                EditorAppearance.tipText.withAlphaComponent(0.06).setFill(); path.fill()
                EditorAppearance.tipText.withAlphaComponent(0.18).setStroke(); path.lineWidth = 0.5; path.stroke()
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: EditorAppearance.tipText]
                let textSize = (label as NSString).size(withAttributes: attributes)
                (label as NSString).draw(at: NSPoint(x: x + (width - textSize.width) / 2,
                                                   y: (height - textSize.height) / 2), withAttributes: attributes)
                x += width + gap
            }
            return true
        }
        image.cacheMode = .never
        return image
    }
}
