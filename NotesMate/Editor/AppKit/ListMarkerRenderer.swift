import AppKit
import CoreText

enum ListMarkerRenderer {
    static func font(for kind: ListKind) -> NSFont {
        .systemFont(ofSize: kind == .unordered ? 8 : 14)
    }
    static func firstLine(_ index: Int, document: EditorDocument, map: PositionMap, view: NSTextView) -> (NSRect, CGFloat)? {
        guard let layout = view.layoutManager, let container = view.textContainer else { return nil }
        layout.ensureLayout(for: container)
        let location = map.starts[index]
        if location == map.length && document.paragraphs[index].isEmpty {
            let rect = layout.extraLineFragmentRect
            let font = TextKitRenderer.font(for: .plain, block: document.paragraphs[index].kind)
            return (rect, rect.minY + layout.defaultBaselineOffset(for: font))
        }
        guard location < (view.textStorage?.length ?? 0) else { return nil }
        let glyph = layout.glyphIndexForCharacter(at: location)
        guard glyph < layout.numberOfGlyphs else { return nil }
        let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let font = TextKitRenderer.font(for: .plain, block: document.paragraphs[index].kind)
        let baseline = rect.minY + (document.paragraphs[index].isEmpty
            ? layout.defaultBaselineOffset(for: font) : layout.location(forGlyphAt: glyph).y)
        return (rect, baseline)
    }

    static func draw(_ bridge: AppKitInputBridge, in view: NSTextView, dirtyRect: NSRect) {
        guard let layout = view.layoutManager, let container = view.textContainer else { return }
        let origin = view.textContainerOrigin
        let visible = dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layout.glyphRange(forBoundingRect: visible, in: container)
        let charRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let presentation = bridge.presentation
        let document = presentation.document
        let items = presentation.lists
        let map = presentation.positions
        let first = map.position(at: min(charRange.location, map.length)).index
        let last = map.position(at: min(NSMaxRange(charRange), map.length)).index
        for index in first...last {
            guard let item = items[index], let (rect, baseline) = firstLine(index, document: document, map: map, view: view), rect.intersects(visible) else { continue }
            let font = font(for: item.kind)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: TextKitRenderer.textColor]
            let width = (item.marker as NSString).size(withAttributes: attrs).width
            let x = origin.x + container.lineFragmentPadding + CGFloat(item.depth) * 22 - 4 - width
            var y = origin.y + baseline - font.ascender
            if item.kind == .unordered {
                // Symbols use a smaller font, so sharing the text baseline makes them sit low.
                // Center their actual outlines on the body's cap-height center; line fragment
                // centers include leading/line spacing and would shift the symbols downward.
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: item.marker, attributes: attrs))
                let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                let location = map.starts[index]
                let bodyFont = location < (view.textStorage?.length ?? 0)
                    ? view.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
                    : nil
                let textFont = bodyFont ?? TextKitRenderer.font(for: .plain, block: document.paragraphs[index].kind)
                y += bounds.midY - textFont.capHeight / 2
            }
            (item.marker as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }
    }

    static func gutterTarget(_ point: NSPoint, bridge: AppKitInputBridge, view: NSTextView) -> NSPoint? {
        guard let layout = view.layoutManager, let container = view.textContainer else { return nil }
        layout.ensureLayout(for: container)
        let local = NSPoint(x: point.x - view.textContainerOrigin.x, y: point.y - view.textContainerOrigin.y)
        let char: Int
        if layout.extraLineFragmentRect.contains(NSPoint(x: max(0, local.x), y: local.y)) {
            char = bridge.positionMap.length
        } else {
            char = layout.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        }
        let index = bridge.positionMap.position(at: char).index
        guard let list = bridge.document.paragraphs[index].kind.list,
              let (rect, _) = firstLine(index, document: bridge.document, map: bridge.positionMap, view: view) else { return nil }
        let x = view.textContainerOrigin.x + container.lineFragmentPadding + CGFloat(list.depth) * 22
        guard point.x < x else { return nil }
        return NSPoint(x: x + 0.5, y: view.textContainerOrigin.y + rect.midY)
    }
}
