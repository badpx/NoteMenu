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
        view.font = .systemFont(ofSize: 14)
        view.textColor = .textColor
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
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let bridge else { super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange); return }
        bridge.runMarkedInput {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        }
    }

    override func unmarkText() {
        super.unmarkText()
        bridge?.finishComposition()
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), let bridge, !bridge.isComposing else { super.insertNewline(sender); return }
        bridge.execute(.newline, name: "换行")
    }

    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText(), let bridge, !bridge.isComposing else { super.insertTab(sender); return }
        bridge.execute(.indent(1), name: "增加层级")
    }

    override func insertBacktab(_ sender: Any?) {
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
        super.draw(dirtyRect)
        guard let bridge else { return }
        ListMarkerRenderer.draw(bridge, in: self, dirtyRect: dirtyRect)
        if bridge.document.isPristine && !bridge.isComposing {
            let origin = textContainerOrigin
            let padding = textContainer?.lineFragmentPadding ?? 0
            ("现在的想法是…" as NSString).draw(at: NSPoint(x: origin.x + padding, y: origin.y), withAttributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.placeholderTextColor,
            ])
        }
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
