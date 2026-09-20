import AppKit

enum ClipboardCodec {
    static let fragmentType = NSPasteboard.PasteboardType("com.notemenu.editor-fragment.v1")
    private struct Envelope: Codable { var version = 1; var document: EditorDocument }

    static func imageAsset(_ image: NSImage) -> ImageAsset? {
        guard let data = NotesSaver.pngData(for: image), image.size.width > 0, image.size.height > 0 else { return nil }
        return ImageAsset(data: data, width: image.size.width, height: image.size.height)
    }

    static func imageFragment(_ images: [NSImage]) -> EditorDocument {
        var result = EditorDocument()
        for image in images {
            guard let asset = imageAsset(image) else { continue }
            let id = UUID()
            result.assets[id] = asset
            result.paragraphs[0].runs.append(.image(id))
        }
        return result
    }

    static func images(on pasteboard: NSPasteboard) -> [NSImage] {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) { return [image] }
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.compactMap { NSImage(contentsOf: $0) }
    }

    static func read(_ pasteboard: NSPasteboard, plainOnly: Bool = false, style: InlineStyle = .plain) -> (EditorDocument, Bool)? {
        if !plainOnly {
            if let data = pasteboard.data(forType: fragmentType), let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
               envelope.version == 1, let valid = try? envelope.document.validated(),
               valid.assets.values.allSatisfy({ NSImage(data: $0.data) != nil }) {
                return (remapped(valid), true)
            }
            let images = images(on: pasteboard)
            if !images.isEmpty { return (imageFragment(images), false) }
            for (type, format) in [(NSPasteboard.PasteboardType.rtfd, NSAttributedString.DocumentType.rtfd), (.rtf, .rtf), (.html, .html)] {
                if let data = pasteboard.data(forType: type),
                   let attributed = try? NSAttributedString(data: data, options: [.documentType: format], documentAttributes: nil) {
                    return (importRich(attributed), true)
                }
            }
        }
        if let plain = pasteboard.string(forType: .string) { return (.plain(plain, style: style), false) }
        return nil
    }

    static func write(_ fragment: EditorDocument, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if let data = try? JSONEncoder().encode(Envelope(document: fragment)) { pasteboard.setData(data, forType: fragmentType) }
        let rendered = TextKitRenderer.render(fragment, exchange: true)
        if let data = rendered.rtfd(from: NSRange(location: 0, length: rendered.length), documentAttributes: [:]) {
            pasteboard.setData(data, forType: .rtfd)
        }
        pasteboard.setString(fragment.text.replacingOccurrences(of: "\u{FFFC}", with: ""), forType: .string)
    }

    static func remapped(_ source: EditorDocument) -> EditorDocument {
        var result = source
        let mapping = Dictionary(uniqueKeysWithValues: source.assets.keys.map { ($0, UUID()) })
        result.assets = Dictionary(uniqueKeysWithValues: source.assets.map { (mapping[$0.key]!, $0.value) })
        for i in result.paragraphs.indices {
            result.paragraphs[i].id = UUID()
            for j in result.paragraphs[i].runs.indices {
                if let id = result.paragraphs[i].runs[j].assetID { result.paragraphs[i].runs[j].assetID = mapping[id] }
            }
        }
        result.revision = 0
        return result
    }

    static func importRich(_ attributed: NSAttributedString) -> EditorDocument {
        let string = attributed.string as NSString
        var result = EditorDocument(paragraphs: [])
        var location = 0
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let attrs = attributed.attributes(at: location, effectiveRange: nil)
            let lists = (attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
            let kind: BlockKind = lists.last.map { .list($0.markerFormat == .decimal ? .ordered : .unordered, min(3, lists.count)) } ?? .body
            var paragraph = Paragraph(kind: kind)
            var contentLength = range.length
            while contentLength > 0, [UInt16(10), 13, 0x2029].contains(string.character(at: location + contentLength - 1)) { contentLength -= 1 }
            attributed.enumerateAttributes(in: NSRange(location: location, length: contentLength)) { attributes, subrange, _ in
                if let attachment = attributes[.attachment] as? NSTextAttachment {
                    let image = attachment.image ?? attachment.fileWrapper?.regularFileContents.flatMap(NSImage.init(data:)) ?? attachment.contents.flatMap(NSImage.init(data:))
                    if let image, let asset = imageAsset(image) {
                        let id = UUID(); result.assets[id] = asset; paragraph.runs.append(.image(id))
                    }
                    return
                }
                let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 14)
                let traits = NSFontManager.shared.traits(of: font)
                let mono = traits.contains(.fixedPitchFontMask) || font.isFixedPitch
                let size = mono ? 12 : font.pointSize >= 23 ? 24 : font.pointSize >= 17 ? 18 : 14
                var marks: InlineMarks = []
                if traits.contains(.boldFontMask) { marks.insert(.bold) }
                if traits.contains(.italicFontMask) || ((attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0) != 0 { marks.insert(.italic) }
                if ((attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0 { marks.insert(.underline) }
                if ((attributes[.strikethroughStyle] as? NSNumber)?.intValue ?? 0) != 0 { marks.insert(.strike) }
                paragraph.runs.append(InlineRun(text: string.substring(with: subrange), style: InlineStyle(marks: marks, font: FontIntent(size: size, monospaced: mono))))
            }
            paragraph.runs = Paragraph.coalesced(paragraph.runs)
            result.paragraphs.append(paragraph)
            location = NSMaxRange(range)
        }
        if result.paragraphs.isEmpty || (string.length > 0 && [UInt16(10), 13, 0x2029].contains(string.character(at: string.length - 1))) {
            result.paragraphs.append(Paragraph())
        }
        return result
    }
}
