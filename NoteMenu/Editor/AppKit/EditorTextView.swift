import AppKit

final class EditorTextView: NSTextView {
    weak var bridge: AppKitInputBridge?

    static func make() -> EditorTextView {
        let storage = NSTextStorage()
        let layout = EditorLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = EditorTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 200), textContainer: container)
        view.isRichText = true
        view.allowsUndo = true
        view.importsGraphics = true
        view.allowsImageEditing = false
        view.usesFontPanel = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.font = .systemFont(ofSize: 15)
        view.textColor = TextKitRenderer.textColor
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        container.widthTracksTextView = true
        view.registerForDraggedTypes([.fileURL, .png, .tiff, .rtfd, .rtf, .string, ClipboardCodec.fragmentType])
        return view
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let bridge else { super.insertText(insertString, replacementRange: replacementRange); return }
        let string = (insertString as? NSAttributedString)?.string ?? (insertString as? String) ?? ""
        let wasMarked = hasMarkedText() || bridge.isComposing
        bridge.runNative(inserted: wasMarked ? nil : string) {
            let range = !wasMarked && !string.isEmpty
                ? separateImageLine(replacementRange: replacementRange) : replacementRange
            super.insertText(insertString, replacementRange: range)
        }
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let bridge else { super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange); return }
        let beginsComposition = !hasMarkedText() && !bridge.isComposing
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        bridge.runMarkedInput {
            let range = beginsComposition && !text.isEmpty
                ? separateImageLine(replacementRange: replacementRange) : replacementRange
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: range)
        }
    }

    private func separateImageLine(replacementRange: NSRange) -> NSRange {
        guard let bridge else { return replacementRange }
        let range = replacementRange.location == NSNotFound ? self.selectedRange() : replacementRange
        let padding = bridge.imageBoundaryPadding(for: range)
        guard padding.before || padding.after else { return replacementRange }
        // Run inside the caller's native/IME transaction so separation and text undo together.
        super.insertText((padding.before ? "\n" : "") + (padding.after ? "\n" : ""), replacementRange: range)
        let insertion = NSRange(location: range.location + (padding.before ? 1 : 0), length: 0)
        setSelectedRange(insertion)
        return insertion
    }

    override func unmarkText() {
        super.unmarkText()
        bridge?.finishComposition()
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), let bridge, !bridge.isComposing else { super.insertNewline(sender); return }
        bridge.execute(.newline, name: "换行")
    }

    override func moveDown(_ sender: Any?) {
        guard isEditable, !hasMarkedText(), let bridge, !bridge.isComposing,
              selectedRange().length == 0, let layout = layoutManager, let container = textContainer else {
            super.moveDown(sender); return
        }
        let map = bridge.positionMap
        let position = map.position(at: selectedRange().location)
        let paragraph = bridge.document.paragraphs[position.index]
        // Existing following paragraphs use native vertical navigation. Only extend EOF.
        guard position.index == bridge.document.paragraphs.count - 1, paragraph.kind.isCode else {
            super.moveDown(sender); return
        }
        layout.ensureLayout(for: container)
        if !paragraph.isEmpty {
            let character = min(selectedRange().location, map.length - 1)
            let glyph = layout.glyphIndexForCharacter(at: character)
            var lineRange = NSRange()
            _ = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
            guard NSMaxRange(lineRange) == layout.numberOfGlyphs else {
                super.moveDown(sender); return
            }
        }
        bridge.execute(.exitCodeAtDocumentEnd, name: "退出代码块")
    }

    override func insertTab(_ sender: Any?) {
        guard isEditable else { return }
        guard !hasMarkedText(), let bridge, !bridge.isComposing else { super.insertTab(sender); return }
        let indices = bridge.positionMap.paragraphs(in: bridge.state.session.selection)
        if indices.contains(where: {
            let kind = bridge.document.paragraphs[$0].kind
            return kind.list != nil || kind.isCode
        }) {
            bridge.execute(.indent(1), name: "增加缩进")
        } else {
            insertText("\t", replacementRange: selectedRange())
        }
    }

    override func insertBacktab(_ sender: Any?) {
        guard isEditable else { return }
        guard !hasMarkedText(), let bridge, !bridge.isComposing else { super.insertBacktab(sender); return }
        bridge.execute(.indent(-1), name: "减少层级")
    }

    override func deleteBackward(_ sender: Any?) {
        guard let bridge, !bridge.isComposing else { super.deleteBackward(sender); return }
        var candidate = bridge.state
        if EditorReducer.apply(.backspaceAtStart, to: &candidate) {
            bridge.execute(.backspaceAtStart, name: "退出段落格式")
        } else { bridge.runNative { super.deleteBackward(sender) } }
    }

    override func deleteForward(_ sender: Any?) {
        guard let bridge, !bridge.isComposing else { super.deleteForward(sender); return }
        bridge.runNative { super.deleteForward(sender) }
    }

    override func deleteWordBackward(_ sender: Any?) {
        guard let bridge, !bridge.isComposing else { super.deleteWordBackward(sender); return }
        bridge.runNative { super.deleteWordBackward(sender) }
    }

    override func deleteWordForward(_ sender: Any?) {
        guard let bridge, !bridge.isComposing else { super.deleteWordForward(sender); return }
        bridge.runNative { super.deleteWordForward(sender) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEditable else { return false }
        guard let bridge else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let key = event.charactersIgnoringModifiers?.lowercased()
        let isFormatShortcut = (flags == .command && ["b", "i", "u"].contains(key ?? ""))
            || (flags == [.command, .shift] && key == "x")
        // Only explicit format shortcuts may end composition; candidate controls remain native.
        if bridge.isComposing && !isFormatShortcut { return false }
        if flags == .command && [UInt16(36), 76].contains(event.keyCode) { bridge.requestSave(); return true }
        if flags == .command {
            switch key {
            case "b": bridge.execute(.toggle(.bold), name: "粗体"); return true
            case "i": bridge.execute(.toggle(.italic), name: "斜体"); return true
            case "u": bridge.execute(.toggle(.underline), name: "下划线"); return true
            case "z": undo(nil); return true
            case "a": selectAll(nil); return true
            case "c": copy(nil); return true
            case "x": cut(nil); return true
            case "v": paste(nil); return true
            default: break
            }
        }
        if flags == [.command, .shift] {
            if key == "x" { bridge.execute(.toggle(.strike), name: "删除线"); return true }
            if key == "z" { redo(nil); return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func undo(_ sender: Any?) {
        guard let bridge, !bridge.isComposing else { return }
        bridge.history.sealTyping(in: self)
        if bridge.history.manager.canUndo { bridge.history.manager.undo() }
    }

    @objc func redo(_ sender: Any?) {
        guard let bridge, !bridge.isComposing else { return }
        bridge.history.sealTyping(in: self)
        if bridge.history.manager.canRedo { bridge.history.manager.redo() }
    }

    override func paste(_ sender: Any?) { bridge?.paste(from: .general) }
    override func pasteAsPlainText(_ sender: Any?) { bridge?.paste(from: .general, plainOnly: true) }
    override func pasteAsRichText(_ sender: Any?) { bridge?.paste(from: .general) }
    override func copy(_ sender: Any?) { bridge?.copy(to: .general) }
    override func cut(_ sender: Any?) { bridge?.copy(to: .general, cut: true) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { bridge?.isComposing == true ? [] : .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { bridge?.isComposing == true ? [] : .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let bridge, !bridge.isComposing, ClipboardCodec.read(sender.draggingPasteboard) != nil else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        bridge.select(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        bridge.paste(from: sender.draggingPasteboard)
        return true
    }

    override func changeFont(_ sender: Any?) { /* All formatting goes through editor commands. */ }
    override func changeColor(_ sender: Any?) {}
    @objc func toggleUnderline(_ sender: Any?) { bridge?.execute(.toggle(.underline), name: "下划线") }

    /// Storage-only transactions do not run NSTextView's native key-edit sizing path.
    /// Include the glyphless final line in the document height before revealing it.
    func scrollSelectionAfterLayout() {
        guard let layout = layoutManager, let container = textContainer,
              let scroll = enclosingScrollView else {
            scrollRangeToVisible(selectedRange())
            return
        }
        layout.ensureLayout(for: container)
        let lastLine = layout.extraLineFragmentRect
        let bottom = max(layout.usedRect(for: container).maxY, lastLine.maxY)
        let height = max(scroll.contentSize.height, ceil(bottom + 2 * textContainerInset.height))
        if frame.height != height { setFrameSize(NSSize(width: frame.width, height: height)) }
        let selection = selectedRange()
        if selection.length == 0, selection.location == textStorage?.length,
           bridge?.document.paragraphs.last?.isEmpty == true, !lastLine.isEmpty {
            // Only reveal the line vertically; native caret drawing and coordinates stay native.
            let target = NSRect(x: textContainerOrigin.x + container.lineFragmentPadding,
                                y: textContainerOrigin.y + lastLine.minY, width: 1, height: lastLine.height)
            scrollToVisible(target.insetBy(dx: 0, dy: -2))
        } else {
            scrollRangeToVisible(selection)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCodeBackgrounds(in: dirtyRect)
        super.draw(dirtyRect)
        guard let bridge else { return }
        ListMarkerRenderer.draw(bridge, in: self, dirtyRect: dirtyRect)
        if bridge.document.isPristine && !bridge.isComposing {
            let origin = textContainerOrigin
            let padding = textContainer?.lineFragmentPadding ?? 0
            ("现在的想法是…" as NSString).draw(at: NSPoint(x: origin.x + padding, y: origin.y), withAttributes: [
                .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.placeholderTextColor,
            ])
        }
    }

    private func drawCodeBackgrounds(in dirtyRect: NSRect) {
        for rect in codeBackgroundRects() where rect.intersects(dirtyRect) {
            TextKitRenderer.codeBackgroundColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        }
    }

    func codeBackgroundRects() -> [NSRect] {
        guard let bridge, let layout = layoutManager, let container = textContainer else { return [] }
        layout.ensureLayout(for: container)
        var backgrounds: [NSRect] = []
        let presentation = bridge.presentation
        let paragraphs = presentation.document.paragraphs
        let map = presentation.positions
        var index = 0
        while index < paragraphs.count {
            guard paragraphs[index].kind.isCode else { index += 1; continue }
            let start = index
            while index + 1 < paragraphs.count, paragraphs[index + 1].kind.isCode { index += 1 }
            let end = index
            index += 1
            let range = NSRange(location: map.starts[start],
                                length: NSMaxRange(map.range(of: end, includingSeparator: true)) - map.starts[start])
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var blockRect = NSRect.null
            layout.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, lineGlyphs, _ in
                let character = layout.characterIndexForGlyph(at: lineGlyphs.location)
                let font = self.textStorage?.attribute(.font, at: character, effectiveRange: nil) as? NSFont
                    ?? TextKitRenderer.font(for: .plain, block: .codeLine)
                let paragraphIndex = map.position(at: character).index
                let baselineOffset = paragraphs[paragraphIndex].isEmpty
                    ? layout.defaultBaselineOffset(for: font)
                    : layout.location(forGlyphAt: lineGlyphs.location).y
                let baseline = rect.minY + baselineOffset
                // Fragment height includes paragraph spacing when followed by another
                // paragraph. Paint from font metrics so adding a body line cannot resize it.
                blockRect = blockRect.union(NSRect(x: rect.minX, y: baseline - font.ascender,
                                                  width: rect.width, height: font.ascender - font.descender))
            }
            // An empty final code paragraph has no glyph; include its native caret line.
            if end == paragraphs.count - 1, paragraphs[end].isEmpty {
                let rect = layout.extraLineFragmentRect
                let font = TextKitRenderer.font(for: .plain, block: .codeLine)
                let baseline = rect.minY + layout.defaultBaselineOffset(for: font)
                blockRect = blockRect.union(NSRect(x: rect.minX, y: baseline - font.ascender,
                                                  width: rect.width, height: font.ascender - font.descender))
            }
            guard !blockRect.isNull, blockRect.height > 0 else { continue }
            blockRect.origin.x = textContainerOrigin.x + max(0, container.lineFragmentPadding)
            blockRect.origin.y += textContainerOrigin.y - TextKitRenderer.codeVerticalPadding
            blockRect.size.height += 2 * TextKitRenderer.codeVerticalPadding
            blockRect.size.width = max(0, container.containerSize.width - 2 * max(0, container.lineFragmentPadding))
            // Paragraph spacing may be part of the final line fragment. Keep it
            // outside the painted background, including next to a trailing empty body.
            if start > 0 {
                let precedingGlyph = layout.glyphIndexForCharacter(at: map.starts[start] - 1)
                let preceding = layout.lineFragmentRect(forGlyphAt: precedingGlyph, effectiveRange: nil)
                let top = max(blockRect.minY, textContainerOrigin.y + preceding.maxY + TextKitRenderer.codeBlockSpacing)
                blockRect.size.height = max(0, blockRect.maxY - top)
                blockRect.origin.y = top
            }
            if end + 1 < paragraphs.count {
                let nextStart = map.starts[end + 1]
                let next = nextStart == map.length
                    ? layout.extraLineFragmentRect
                    : layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: nextStart), effectiveRange: nil)
                let bottom = min(blockRect.maxY, textContainerOrigin.y + next.minY - TextKitRenderer.codeBlockSpacing)
                blockRect.size.height = max(0, bottom - blockRect.minY)
            }
            backgrounds.append(blockRect)
        }
        return backgrounds
    }

    override func mouseDown(with event: NSEvent) {
        if let bridge, !bridge.isComposing,
           let point = ListMarkerRenderer.gutterTarget(convert(event.locationInWindow, from: nil), bridge: bridge, view: self),
           let adjusted = NSEvent.mouseEvent(with: event.type, location: convert(point, to: nil), modifierFlags: event.modifierFlags,
               timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil, eventNumber: event.eventNumber,
               clickCount: event.clickCount, pressure: event.pressure) {
            super.mouseDown(with: adjusted)
        } else { super.mouseDown(with: event) }
    }

    override func resetCursorRects() {
        addCursorRect(NSRect(x: 6, y: 6, width: max(0, bounds.width - 12), height: max(0, bounds.height - 6)), cursor: .iBeam)
    }
}
