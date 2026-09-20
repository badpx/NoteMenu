import AppKit

/// 列表标记绘制与排水区几何（EditorSpec §5.1 / §6）。
/// 格式真值来自 EditorDocument（含空段落），几何统一来自 NSLayoutManager 行片段矩形。
enum MarkerRenderer {
    /// 该段落正文起点（排水区右缘）：光标 x 的下限。
    static func textStartX(in textView: NSTextView, format: ParagraphFormat) -> CGFloat {
        let padding = textView.textContainer?.lineFragmentPadding ?? 5
        let indent = format.isList ? ListLayout.headIndent(level: format.listLevel) : 0
        return padding + indent
    }

    /// 点击点（容器坐标）是否落在排水区内；用于把光标吸附到段落首字符前。
    static func isInGutter(containerPoint: NSPoint, format: ParagraphFormat, textView: NSTextView) -> Bool {
        containerPoint.x < textStartX(in: textView, format: format)
    }

    static func drawMarkers(in textView: NSTextView, document: EditorDocument) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)

        let formats = (0..<document.paragraphCount).map { document.format(at: $0) }
        let numbers = ListLayout.numbers(for: formats)
        let gutterLeft = textView.textContainerInset.width + textContainer.lineFragmentPadding

        for (index, format) in formats.enumerated() {
            guard format.isList, let number = numbers[index] else { continue }
            let marker = ListLayout.markerText(
                ordered: format.ordered, number: number, level: format.listLevel
            )
            let paragraphRange = document.paragraphRange(at: index)

            let lineRect: NSRect
            let markerFont: NSFont
            if paragraphRange.length > 0, let storage = textView.textStorage {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: paragraphRange.location)
                guard glyphIndex < layoutManager.numberOfGlyphs else { continue }
                lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                markerFont = (storage.attribute(.font, at: paragraphRange.location, effectiveRange: nil) as? NSFont)
                    ?? textView.font ?? defaultFont
            } else {
                // 末尾空段落：无字符可挂样式，用 extraLineFragment + 输入属性字体
                lineRect = layoutManager.extraLineFragmentRect
                guard lineRect != .zero else { continue }
                markerFont = (textView.typingAttributes[.font] as? NSFont)
                    ?? textView.font ?? defaultFont
            }

            // baselineOffset 是基线到行框底部的距离；
            // draw(at:) 的点对应字形 ascender 顶端（基线在点下方 ascender 处）。
            let baseline: CGFloat
            if paragraphRange.length > 0 {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: paragraphRange.location)
                baseline = lineRect.maxY
                    - layoutManager.typesetter.baselineOffset(in: layoutManager, glyphIndex: glyphIndex)
            } else {
                baseline = lineRect.minY + markerFont.ascender
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: markerFont,
                .foregroundColor: NSColor.textColor,
            ]
            let markerSize = (marker as NSString).size(withAttributes: attributes)
            // 右对齐于排水区右缘内侧 4px
            let gutterRight = gutterLeft + ListLayout.headIndent(level: format.listLevel)
            let point = NSPoint(
                x: gutterRight - ListLayout.markerTrailingGap - markerSize.width,
                y: textView.textContainerInset.height + baseline - markerFont.ascender
            )
            (marker as NSString).draw(at: point, withAttributes: attributes)
        }
    }

    private static var defaultFont: NSFont {
        NSFont.systemFont(ofSize: HTMLExporter.bodyFontSize)
    }
}
