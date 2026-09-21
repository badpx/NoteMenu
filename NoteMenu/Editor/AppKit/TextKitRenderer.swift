import AppKit

extension NSAttributedString.Key {
    static let editorStyle = Self("NoteMenu.InlineStyle.v1")
    static let editorAsset = Self("NoteMenu.Asset.v1")
}

/// Supplies real layout geometry for the zero-length last paragraph, including when the caret is elsewhere.
final class EditorLayoutManager: NSLayoutManager {
    var trailingKind: BlockKind = .body
    override func ensureLayout(for container: NSTextContainer) {
        super.ensureLayout(for: container)
        // TextKit can leave an empty document's extra fragment invalid after a zero-length
        // style-only transaction. Supply it here, in the layout layer, not by moving the caret.
        if textStorage?.length == 0 && extraLineFragmentRect.isEmpty {
            let height = defaultLineHeight(for: TextKitRenderer.font(for: .plain, block: trailingKind))
            setExtraLineFragmentRect(NSRect(x: 0, y: 0, width: container.containerSize.width, height: height),
                                    usedRect: NSRect(x: 0, y: 0, width: 10, height: height), textContainer: container)
        }
    }
    override func setExtraLineFragmentRect(_ fragmentRect: NSRect, usedRect: NSRect, textContainer container: NSTextContainer) {
        var fragment = fragmentRect
        var used = usedRect
        let font = TextKitRenderer.font(for: .plain, block: trailingKind)
        fragment.size.height = defaultLineHeight(for: font)
        used.origin.x = trailingKind.isCode ? TextKitRenderer.codeHorizontalPadding : CGFloat(trailingKind.list?.depth ?? 0) * 22
        used.size.height = fragment.height
        super.setExtraLineFragmentRect(fragment, usedRect: used, textContainer: container)
    }
}

enum TextKitRenderer {
    static let textColor = NSColor(srgbRed: 50 / 255, green: 50 / 255, blue: 50 / 255, alpha: 1)
    static let codeBackgroundColor = NSColor(srgbRed: 234 / 255, green: 234 / 255, blue: 234 / 255, alpha: 1)
    static let codeHorizontalPadding: CGFloat = 4
    static let codeVerticalPadding: CGFloat = 2
    static let codeBlockSpacing: CGFloat = 2
    static func paragraphStyle(_ kind: BlockKind, includeNativeLists: Bool = false) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = kind == .body || kind.list != nil ? 6 : 4
        style.paragraphSpacing = kind == .body || kind.list != nil ? 4 : 0
        style.paragraphSpacingBefore = 0
        if kind.isCode {
            style.headIndent = codeHorizontalPadding
            style.firstLineHeadIndent = codeHorizontalPadding
            style.tailIndent = -codeHorizontalPadding
        }
        if let list = kind.list {
            style.headIndent = CGFloat(list.depth) * 22
            style.firstLineHeadIndent = style.headIndent
            if includeNativeLists {
                style.textLists = (1...list.depth).map { depth in
                    NSTextList(markerFormat: list.kind == .ordered ? .decimal : NSTextList.MarkerFormat(rawValue: ListResolver.unorderedMarkers[depth - 1]), options: 0)
                }
            }
        }
        return style
    }

    static func font(for style: InlineStyle, block: BlockKind) -> NSFont {
        let code = block.isCode || style.marks.contains(.code) || style.font?.monospaced == true
        var size: CGFloat = 15
        var bold = style.marks.contains(.bold)
        if case .heading(let level) = block {
            size = level == 1 ? 22 : level == 2 ? 18 : 15
            bold = true
        }
        if let intent = style.font { size = CGFloat(intent.size) }
        if code { size = 14 }
        let base = code ? (NSFont(name: "Courier", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)) : .systemFont(ofSize: size)
        return bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
    }

    static func attributes(_ style: InlineStyle, block: BlockKind, exchange: Bool = false) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [
            .font: font(for: style, block: block), .foregroundColor: exchange ? NSColor.textColor : textColor,
            .paragraphStyle: paragraphStyle(block, includeNativeLists: exchange),
        ]
        if style.marks.contains(.italic) { result[.obliqueness] = 0.25 }
        if style.marks.contains(.underline) { result[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.marks.contains(.strike) { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if !exchange {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            result[.editorStyle] = try? encoder.encode(style)
        }
        return result
    }

    static func renderParagraph(_ paragraph: Paragraph, assets: [UUID: ImageAsset], separator: Bool, exchange: Bool = false) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        for run in paragraph.runs {
            var attrs = attributes(run.style, block: paragraph.kind, exchange: exchange)
            if let id = run.assetID, let asset = assets[id] {
                let attachment = NSTextAttachment(data: asset.data, ofType: asset.type)
                attachment.image = NSImage(data: asset.data)
                let scale = min(1, 72 / asset.height)
                attachment.bounds = NSRect(x: 0, y: -2, width: asset.width * scale, height: asset.height * scale)
                attrs[.attachment] = attachment
                if !exchange { attrs[.editorAsset] = id.uuidString }
            }
            output.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        if separator { output.append(NSAttributedString(string: "\n", attributes: attributes(.plain, block: paragraph.kind, exchange: exchange))) }
        return output
    }

    static func render(_ document: EditorDocument, exchange: Bool = false) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        for i in document.paragraphs.indices {
            output.append(renderParagraph(document.paragraphs[i], assets: document.assets, separator: i < document.paragraphs.count - 1, exchange: exchange))
        }
        if !exchange { applyCodePadding(document, to: output) }
        return output
    }

    /// Only replace the changed paragraph span. Unrelated storage, glyphs and scroll position survive.
    static func apply(_ document: EditorDocument, previous: EditorDocument?, to view: NSTextView) {
        guard let storage = view.textStorage else { return }
        (view.layoutManager as? EditorLayoutManager)?.trailingKind = document.paragraphs.last!.kind
        var first = 0, oldEnd = previous?.paragraphs.count ?? 0, newEnd = document.paragraphs.count
        if let previous {
            while first < min(oldEnd, newEnd), previous.paragraphs[first] == document.paragraphs[first] { first += 1 }
            while oldEnd > first, newEnd > first, previous.paragraphs[oldEnd - 1] == document.paragraphs[newEnd - 1] {
                oldEnd -= 1; newEnd -= 1
            }
            // The last equal paragraph may acquire or lose its separator.
            if oldEnd != newEnd && first > 0 { first -= 1 }
        }
        let oldMap = previous.map(PositionMap.init)
        let newMap = PositionMap(document)
        let location = first < newMap.starts.count ? newMap.starts[first] : document.length
        let oldLimit = oldMap.map { oldEnd < $0.starts.count ? $0.starts[oldEnd] : $0.length } ?? storage.length
        let replacement = NSMutableAttributedString(string: "")
        if first < newEnd {
            for i in first..<newEnd {
                replacement.append(renderParagraph(document.paragraphs[i], assets: document.assets, separator: i < document.paragraphs.count - 1))
            }
        }
        let range = NSRange(location: min(location, storage.length), length: max(0, min(oldLimit, storage.length) - min(location, storage.length)))
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: replacement)
        storage.endEditing()
        updateGeometry(document, view: view)
    }

    /// Native input already changed the characters; only decorate the affected paragraphs.
    static func decorate(_ document: EditorDocument, indices: ClosedRange<Int>, view: NSTextView) {
        guard let storage = view.textStorage else { return }
        let map = PositionMap(document)
        (view.layoutManager as? EditorLayoutManager)?.trailingKind = document.paragraphs.last!.kind
        storage.beginEditing()
        for i in indices {
            let rendered = renderParagraph(document.paragraphs[i], assets: document.assets, separator: i < document.paragraphs.count - 1)
            rendered.enumerateAttributes(in: NSRange(location: 0, length: rendered.length)) { attrs, range, _ in
                let target = NSRange(location: map.starts[i] + range.location, length: range.length)
                if NSMaxRange(target) <= storage.length { storage.setAttributes(attrs, range: target) }
            }
        }
        storage.endEditing()
        updateGeometry(document, view: view)
    }

    private static func applyCodePadding(_ document: EditorDocument, to storage: NSMutableAttributedString) {
        // Block boundary spacing must be identical in full and incremental projections.
        let map = PositionMap(document)
        storage.beginEditing()
        for i in document.paragraphs.indices where document.paragraphs[i].kind.isCode {
            let style = paragraphStyle(.codeLine).mutableCopy() as! NSMutableParagraphStyle
            if i == 0 || !document.paragraphs[i - 1].kind.isCode { style.paragraphSpacingBefore = codeVerticalPadding + (i > 0 ? codeBlockSpacing : 0) }
            if i == document.paragraphs.count - 1 || !document.paragraphs[i + 1].kind.isCode { style.paragraphSpacing = codeVerticalPadding + style.lineSpacing + (i + 1 < document.paragraphs.count ? codeBlockSpacing : 0) }
            let range = map.range(of: i, includingSeparator: true)
            if range.length > 0 { storage.addAttribute(.paragraphStyle, value: style, range: range) }
        }
        storage.endEditing()
    }

    static func updateGeometry(_ document: EditorDocument, view: NSTextView) {
        if let storage = view.textStorage { applyCodePadding(document, to: storage) }
        let markers = ListResolver.resolve(document)
        let maxWidth = markers.values.map { ($0.marker as NSString).size(withAttributes: [.font: ListMarkerRenderer.font(for: $0.kind)]).width }.max() ?? 0
        view.textContainerInset = NSSize(width: max(6, maxWidth + 4 - 22), height: 8)
        view.defaultParagraphStyle = paragraphStyle(document.paragraphs.last!.kind)
        if document.paragraphs.last!.isEmpty {
            view.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: document.length, length: 0), actualCharacterRange: nil)
        }
        view.needsDisplay = true
    }

    static func decodeNative(_ text: NSAttributedString, assets: [UUID: ImageAsset]) -> EditorDocument {
        var result = EditorDocument(paragraphs: [], assets: assets)
        var current = Paragraph()
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            let style = (attrs[.editorStyle] as? Data).flatMap { try? JSONDecoder().decode(InlineStyle.self, from: $0) } ?? .plain
            let piece = (text.string as NSString).substring(with: range)
            if let raw = attrs[.editorAsset] as? String, let id = UUID(uuidString: raw), assets[id] != nil {
                for _ in piece.utf16 { current.runs.append(.image(id)) }
                return
            }
            let parts = piece.components(separatedBy: "\n")
            for (i, part) in parts.enumerated() {
                if i > 0 { result.paragraphs.append(current); current = Paragraph() }
                if !part.isEmpty { current.runs.append(InlineRun(text: part, style: style)) }
            }
        }
        result.paragraphs.append(current)
        for i in result.paragraphs.indices { result.paragraphs[i].runs = Paragraph.coalesced(result.paragraphs[i].runs) }
        return result
    }
}
