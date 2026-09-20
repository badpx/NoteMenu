import AppKit
import XCTest
@testable import NoteMenuEditor

final class EditorAppKitTests: XCTestCase {
    var bridge: AppKitInputBridge!
    var view: EditorTextView!
    override func setUp() {
        super.setUp()
        bridge = AppKitInputBridge()
        view = EditorTextView.make()
        bridge.attach(view)
    }
    override func tearDown() { view = nil; bridge = nil; super.tearDown() }
    func type(_ text: String) {
        for c in text { view.insertText(String(c), replacementRange: NSRange(location: NSNotFound, length: 0)) }
    }
    func assertProjection(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(view.string, bridge.document.text, file: file, line: line)
        let reference = NSTextStorage(attributedString: TextKitRenderer.render(bridge.document))
        reference.fixAttributes(in: NSRange(location: 0, length: reference.length))
        let actual = NSMutableAttributedString(attributedString: view.textStorage!)
        reference.enumerateAttribute(.attachment, in: NSRange(location: 0, length: reference.length)) { value, range, _ in
            guard let expected = value as? NSTextAttachment else { return }
            let attachment = actual.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment
            XCTAssertNotNil(attachment, file: file, line: line)
            XCTAssertEqual(attachment?.bounds, expected.bounds, file: file, line: line)
            XCTAssertEqual(attachment?.contents, expected.contents, file: file, line: line)
            XCTAssertEqual(attachment?.image?.size, expected.image?.size, file: file, line: line)
        }
        // Independent projections allocate independent attachment objects; compare values, not identity.
        actual.removeAttribute(.attachment, range: NSRange(location: 0, length: actual.length))
        reference.removeAttribute(.attachment, range: NSRange(location: 0, length: reference.length))
        XCTAssertEqual(actual, reference, file: file, line: line)
    }

    func testNativeTriggerResetAndUndo_T12_T15_U01_U03() {
        type("**中文**")
        XCTAssertEqual(view.string, "中文")
        XCTAssertTrue(bridge.document.paragraphs[0].runs.first!.style.marks.contains(.bold))
        type("后续")
        XCTAssertEqual(bridge.document.paragraphs[0].runs.last!.style, .plain)
        view.undo(nil)
        XCTAssertEqual(view.string, "中文")
        view.undo(nil)
        XCTAssertEqual(view.string, "**中文**")
        XCTAssertEqual(bridge.state.session.selection.location, 6)
        view.redo(nil)
        XCTAssertEqual(view.string, "中文")
        assertProjection()
    }

    func testEmptyListTypingDeletionAndEOF_M02_M03_L07_U04() {
        type("- ")
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .list(.unordered, 1))
        view.insertTab(nil); view.insertTab(nil)
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .list(.unordered, 3))
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        XCTAssertEqual(view.layoutManager!.extraLineFragmentUsedRect.minX, 66)
        type("a")
        view.deleteBackward(nil)
        XCTAssertTrue(bridge.document.paragraphs[0].isEmpty)
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .list(.unordered, 3))
        view.insertNewline(nil)
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .list(.unordered, 2))
        view.undo(nil)
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .list(.unordered, 3))
        type("a"); view.insertNewline(nil)
        XCTAssertEqual(bridge.document.paragraphs.count, 2)
        XCTAssertEqual(bridge.document.paragraphs[1].kind, .list(.unordered, 3))
        assertProjection()
    }

    func testCrossParagraphNativeDeleteUndo_M10_K12_U05() {
        type("# A"); view.insertNewline(nil); type("B")
        let before = bridge.document.paragraphs
        bridge.select(NSRange(location: 1, length: 1))
        view.deleteForward(nil)
        XCTAssertEqual(view.string, "AB")
        view.undo(nil)
        XCTAssertEqual(bridge.document.paragraphs, before)
        assertProjection()
    }

    func testNativeDeleteWordAndUnicode_M07_K11() {
        type("中👩🏽‍💻e\u{301}")
        view.deleteBackward(nil)
        XCTAssertEqual(view.string, "中👩🏽‍💻")
        view.deleteBackward(nil)
        XCTAssertEqual(view.string, "中")
        bridge.load(.plain("hello word")); bridge.select(NSRange(location: 10, length: 0))
        view.deleteWordBackward(nil)
        XCTAssertEqual(view.string, "hello ")
        assertProjection()
    }

    func testCompositionCommitSkipsTrigger_I01_I02_I04_U06() {
        view.setMarkedText("**中**", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(bridge.isComposing)
        XCTAssertEqual(bridge.document.text, "")
        view.insertText("**中**", replacementRange: view.markedRange())
        XCTAssertFalse(bridge.isComposing)
        XCTAssertEqual(bridge.document.text, "**中**")
        XCTAssertFalse(bridge.document.paragraphs[0].runs[0].style.marks.contains(.bold))
        view.undo(nil)
        XCTAssertEqual(view.string, "")
    }

    func testKeyboardSaveAndFormatting_K14_K17() {
        var saves = 0
        bridge.onSave = { saves += 1 }
        for code: UInt16 in [36, 76] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                        context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code)!
            XCTAssertTrue(view.performKeyEquivalent(with: event))
        }
        XCTAssertEqual(saves, 2)
        bridge.execute(.toggle(.bold)); type("x")
        XCTAssertTrue(bridge.document.paragraphs[0].runs[0].style.marks.contains(.bold))
        bridge.select(NSRange(location: 0, length: 1)); bridge.execute(.toggle(.italic))
        let obliqueness = view.textStorage!.attribute(.obliqueness, at: 0, effectiveRange: nil) as? NSNumber
        XCTAssertEqual(obliqueness?.doubleValue, 0.25)
        bridge.select(NSRange(location: 1, length: 0))
        let selectAll = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        XCTAssertTrue(view.performKeyEquivalent(with: selectAll))
        XCTAssertEqual(bridge.state.session.selection, NSRange(location: 0, length: 1))
    }

    func testFormattingEndsCompositionAndKeepsText() {
        for command: EditorCommand in [.block(.heading(2)), .list(.unordered), .list(.ordered)] {
            bridge.load(EditorDocument())
            view.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            bridge.execute(command)
            XCTAssertFalse(bridge.isComposing)
            XCTAssertFalse(view.hasMarkedText())
            XCTAssertEqual(bridge.document.text, "中文")
            XCTAssertNotEqual(bridge.document.paragraphs[0].kind, .body)
            view.undo(nil)
            XCTAssertEqual(bridge.document.text, "中文")
            XCTAssertEqual(bridge.document.paragraphs[0].kind, .body)
            view.undo(nil)
            XCTAssertEqual(bridge.document.text, "")
        }
    }

    func testFormatShortcutDuringCompositionAndNextInput() {
        view.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
            context: nil, characters: "b", charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11)!
        XCTAssertTrue(view.performKeyEquivalent(with: event))
        XCTAssertFalse(bridge.isComposing)
        XCTAssertTrue(bridge.state.session.insertionStyle.marks.contains(.bold))
        view.setMarkedText("继续", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("继续", replacementRange: view.markedRange())
        XCTAssertEqual(bridge.document.text, "中文继续")
        XCTAssertTrue(bridge.document.paragraphs[0].runs.last!.style.marks.contains(.bold))
        assertProjection()
    }

    func testPastePlainRichAndInternalClipboard_P01_P03_P09_P11() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("- **原文**\n``` ", forType: .string)
        bridge.paste(from: pasteboard)
        XCTAssertEqual(bridge.document.text, "- **原文**\n``` ")
        XCTAssertTrue(bridge.document.paragraphs.allSatisfy { $0.kind == .body })
        let style = NSMutableParagraphStyle()
        style.textLists = [NSTextList(markerFormat: .decimal, options: 0), NSTextList(markerFormat: .disc, options: 0)]
        let rich = NSAttributedString(string: "粘贴", attributes: [.font: NSFont(name: "Times New Roman", size: 23)!,
            .paragraphStyle: style, .underlineStyle: 1, .strikethroughStyle: 1, .link: "https://example.com", .foregroundColor: NSColor.red])
        let fragment = ClipboardCodec.importRich(rich)
        XCTAssertEqual(fragment.paragraphs[0].kind, .list(.unordered, 2))
        XCTAssertEqual(fragment.paragraphs[0].runs[0].style.font?.size, 24)
        bridge.load(fragment)
        bridge.select(NSRange(location: 0, length: fragment.length))
        bridge.copy(to: pasteboard)
        bridge.load(EditorDocument())
        bridge.paste(from: pasteboard)
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .list(.unordered, 2))
        XCTAssertNil(view.textStorage!.attribute(.link, at: 0, effectiveRange: nil))
        assertProjection()
    }

    func testFontTiers_P02_L10() {
        for (size, expected) in [(16, 14), (17, 18), (22, 18), (23, 24)] {
            let rich = NSAttributedString(string: "x", attributes: [.font: NSFont.systemFont(ofSize: CGFloat(size))])
            XCTAssertEqual(ClipboardCodec.importRich(rich).paragraphs[0].runs[0].style.font?.size, expected)
        }
        let mono = NSAttributedString(string: "x", attributes: [.font: NSFont(name: "Courier", size: 24)!])
        XCTAssertEqual(ClipboardCodec.importRich(mono).paragraphs[0].runs[0].style.font, FontIntent(size: 12, monospaced: true))
    }

    func testImageRepresentationsAttachmentsAndUndo_P04_P08_M06_E06() {
        let image = NSImage(size: NSSize(width: 200, height: 100))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 200, height: 100).fill(); image.unlockFocus()
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setData(NotesSaver.pngData(for: image), forType: .png)
        board.setData(image.tiffRepresentation, forType: .tiff)
        bridge.paste(from: board)
        XCTAssertEqual(bridge.document.assetOrder.count, 1)
        let attachment = view.textStorage!.attribute(.attachment, at: 0, effectiveRange: nil) as! NSTextAttachment
        XCTAssertEqual(attachment.bounds.height, 72)
        XCTAssertEqual(attachment.bounds.width, 144)
        XCTAssertFalse(HTMLExporter.export(bridge.document).bodyHTML.contains("\u{FFFC}"))
        view.undo(nil); XCTAssertEqual(bridge.document.assetOrder.count, 0)
        view.redo(nil); XCTAssertEqual(bridge.document.assetOrder.count, 1)
        board.setData(Data([1, 2, 3]), forType: .png)
        XCTAssertEqual(ClipboardCodec.images(on: board).count, 1)
    }

    func testIncrementalProjectionMatchesFullAfterMixedCommands() {
        for input in ["# 标题", "body", "- item", "next", "``` code"] {
            type(input); view.insertNewline(nil); assertProjection()
        }
        bridge.select(NSRange(location: 0, length: bridge.document.length))
        bridge.execute(.list(.ordered)); assertProjection()
        bridge.execute(.indent(1)); assertProjection()
        bridge.execute(.toggle(.strike)); assertProjection()
        for _ in 0..<3 { view.undo(nil); assertProjection() }
        for _ in 0..<3 { view.redo(nil); assertProjection() }
    }

    func testDefaultTypingUndoMatchesNative_U02() {
        final class NativeView: NSTextView {
            let history = UndoManager()
            override var undoManager: UndoManager? { history }
        }
        let native = NativeView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        native.allowsUndo = true
        for c in "hello ** incomplete" {
            native.insertText(String(c), replacementRange: NSRange(location: NSNotFound, length: 0))
            type(String(c))
        }
        native.breakUndoCoalescing()
        if native.history.groupingLevel == 1 { native.history.endUndoGrouping() }
        native.history.undo(); view.undo(nil)
        XCTAssertEqual(view.string, native.string)
        XCTAssertEqual(bridge.history.manager.canUndo, native.history.canUndo)
    }

    func testReplacementRangeAndUnsupportedSyntax_T16_T18() {
        type("**a")
        bridge.select(NSRange(location: 2, length: 1))
        view.insertText("b**", replacementRange: NSRange(location: 2, length: 1))
        XCTAssertEqual(view.string, "b")
        XCTAssertTrue(bridge.document.paragraphs[0].runs[0].style.marks.contains(.bold))
        bridge.load(EditorDocument()); type("- [ ]")
        XCTAssertEqual(view.string, "[ ]")
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .list(.unordered, 1))
        bridge.load(EditorDocument())
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("- [ ]", forType: .string)
        bridge.paste(from: board)
        XCTAssertEqual(view.string, "- [ ]")
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .body)
    }

    func testIMEGatesAndSaveCommit_I03_I05_I06() {
        bridge.execute(.list(.ordered))
        view.insertTab(nil)
        var saved = ""
        bridge.onSave = { saved = self.bridge.document.text }
        view.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(bridge.presentationDocument.paragraphs[0].kind, .list(.ordered, 2))
        XCTAssertEqual(bridge.presentationDocument.text, "中文")
        view.setMarkedText("中文候选", selectedRange: NSRange(location: 4, length: 0), replacementRange: view.markedRange())
        XCTAssertEqual(bridge.presentationDocument.text, "中文候选")
        XCTAssertEqual(bridge.presentation.positions.length, 4)
        for (chars, code) in [("\r", UInt16(36)), ("z", UInt16(6))] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            XCTAssertFalse(view.performKeyEquivalent(with: event))
        }
        XCTAssertEqual(saved, "")
        bridge.requestSave()
        XCTAssertEqual(saved, "中文候选")
        XCTAssertFalse(bridge.isComposing)
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .list(.ordered, 2))
    }

    func testListGutterAndLongNumberGeometry_L05_L08_L12() {
        bridge.execute(.list(.ordered)); view.insertTab(nil)
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        let origin = view.textContainerOrigin
        let target = ListMarkerRenderer.gutterTarget(NSPoint(x: origin.x + 1, y: origin.y + 5), bridge: bridge, view: view)
        XCTAssertNotNil(target)
        XCTAssertGreaterThanOrEqual(target!.x, origin.x + 44)
        type(String(repeating: "word ", count: 40))
        let kind = bridge.document.paragraphs[0].kind
        bridge.select(NSRange(location: 80, length: 0)); view.deleteBackward(nil)
        XCTAssertEqual(bridge.document.paragraphs[0].kind, kind)
        let long = EditorDocument(paragraphs: (0..<110).map { _ in Paragraph(kind: .list(.ordered, 1), runs: [InlineRun(text: "item")]) })
        bridge.load(long)
        XCTAssertEqual(bridge.listItems[99]?.marker, "100.")
        let width = ("100." as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width
        XCTAssertGreaterThanOrEqual(view.textContainerOrigin.x + view.textContainer!.lineFragmentPadding + 22 - 4 - width, 0)
    }

    func testHistoryBranchAndEmptyInputAttributes_U04_U07() {
        bridge.execute(.toggle(.bold))
        view.undo(nil)
        XCTAssertTrue(bridge.state.session.insertionStyle.marks.isEmpty)
        view.redo(nil)
        XCTAssertTrue(bridge.state.session.insertionStyle.marks.contains(.bold))
        type("x")
        view.undo(nil)
        XCTAssertTrue(bridge.history.manager.canRedo)
        type("y")
        XCTAssertFalse(bridge.history.manager.canRedo)
        XCTAssertEqual(view.string, "y")
    }

    func testFinderFilesAndRTFDAttachments_P06_P07() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus(); NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 20, height: 20).fill(); image.unlockFocus()
        let data = try XCTUnwrap(NotesSaver.pngData(for: image))
        let urls = [directory.appendingPathComponent("a.png"), directory.appendingPathComponent("b.png")]
        for url in urls { try data.write(to: url) }
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        XCTAssertTrue(board.writeObjects(urls.map { $0 as NSURL }))
        bridge.paste(from: board)
        XCTAssertEqual(bridge.document.assetOrder.count, 2)
        view.undo(nil); XCTAssertEqual(bridge.document.assetOrder.count, 0)
        let fragment = ClipboardCodec.imageFragment([image, image])
        let rich = NSMutableAttributedString(string: "before")
        rich.append(TextKitRenderer.render(fragment, exchange: true)); rich.append(NSAttributedString(string: "after"))
        let imported = ClipboardCodec.importRich(rich)
        XCTAssertEqual(imported.assetOrder.count, 2)
        XCTAssertEqual(imported.text, "before\u{FFFC}\u{FFFC}after")
        bridge.load(imported)
        bridge.select(NSRange(location: 6, length: 0)); view.insertNewline(nil)
        XCTAssertEqual(bridge.document.assetOrder.count, 2)
    }

    func testLongDocumentLocalInput_L09() {
        let document = EditorDocument(paragraphs: (0..<1500).map { i in
            Paragraph(kind: i % 3 == 0 ? .list(.ordered, 1) : .body, runs: [InlineRun(text: "paragraph \(i) 中文")])
        })
        bridge.load(document)
        bridge.select(NSRange(location: document.length, length: 0))
        let start = Date()
        type("new text")
        let elapsed = Date().timeIntervalSince(start)
        print("PERF 1500 paragraphs / 8 native characters: \(elapsed)s")
        XCTAssertTrue(bridge.document.text.hasSuffix("new text"))
        XCTAssertEqual(bridge.document.paragraphs.count, 1500)
        XCTAssertEqual(bridge.document.paragraphs[0], document.paragraphs[0])
        XCTAssertEqual(bridge.positionMap.starts, PositionMap(bridge.document).starts)
        XCTAssertEqual(bridge.presentation.positions.length, bridge.document.length)
    }

    func testBodyEOFListAndSelectionAffinity_M03_M09() {
        type("a"); view.insertNewline(nil); bridge.execute(.list(.ordered))
        XCTAssertEqual(bridge.document.paragraphs.map(\.kind), [.body, .list(.ordered, 1)])
        type("b")
        bridge.select(NSRange(location: 0, length: 3), affinity: .upstream)
        let before = bridge.state.session
        bridge.execute(.block(.heading(2)))
        view.undo(nil)
        XCTAssertEqual(bridge.state.session, before)
        XCTAssertEqual(view.selectedRange(), before.selection)
        XCTAssertEqual(view.selectionAffinity.rawValue, before.affinity)
    }

    func testResetSurvivesRelayoutAndInlineCodeIsOpaque_T13_T17() {
        type("**bold**")
        view.setFrameSize(NSSize(width: 280, height: 400))
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        view.setSelectedRange(view.selectedRange())
        type(" plain")
        XCTAssertTrue(bridge.document.paragraphs[0].runs.last!.style.marks.isEmpty)
        bridge.load(EditorDocument()); type("`abc`")
        bridge.select(NSRange(location: 1, length: 0)); type("**literal**")
        XCTAssertEqual(view.string, "a**literal**bc")
        XCTAssertTrue(bridge.document.paragraphs[0].runs.allSatisfy { !$0.style.marks.contains(.bold) })
    }

    func testNoopTabDefaultForwardDeleteAndHeadingBackspace_K05_K08_K09() {
        type("abc")
        let before = bridge.state
        view.insertTab(nil); view.insertBacktab(nil)
        XCTAssertEqual(bridge.state, before)
        bridge.execute(.block(.heading(2))); bridge.select(NSRange(location: 0, length: 0))
        view.deleteForward(nil)
        XCTAssertEqual(view.string, "bc")
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .heading(2))
        view.deleteBackward(nil)
        XCTAssertEqual(view.string, "bc"); XCTAssertEqual(bridge.document.paragraphs[0].kind, .body)
        bridge.load(EditorDocument()); bridge.execute(.list(.ordered)); for _ in 0..<8 { view.insertTab(nil) }
        view.undo(nil)
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .list(.ordered, 7))
    }

    func testPasteOnlyTriggersOnFollowingTypedEvent_P10() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("-", forType: .string)
        bridge.paste(from: board)
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .body)
        type(" ")
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .list(.unordered, 1))
        view.undo(nil)
        XCTAssertEqual(view.string, "- ")
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        XCTAssertEqual(view.string, "- ")
    }

    func testStandardRTFDExchange_P03_P11() throws {
        let source = EditorDocument(paragraphs: [
            Paragraph(kind: .list(.ordered, 1), runs: [InlineRun(text: "first")]),
            Paragraph(kind: .list(.unordered, 3), runs: [InlineRun(text: "second", style: InlineStyle(marks: [.bold, .italic, .strike]))]),
        ])
        let rich = TextKitRenderer.render(source, exchange: true)
        let data = try XCTUnwrap(rich.rtfd(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]))
        let decoded = try XCTUnwrap(NSAttributedString(rtfd: data, documentAttributes: nil))
        let imported = ClipboardCodec.importRich(decoded)
        XCTAssertEqual(imported.text, source.text)
        XCTAssertEqual(imported.paragraphs.map(\.kind), source.paragraphs.map(\.kind))
        XCTAssertTrue(imported.paragraphs[1].runs[0].style.marks.contains([.bold, .italic, .strike]))
    }

    func testIMEReplacesParagraphsAsOneTransaction_U06() {
        let source = EditorDocument(paragraphs: [Paragraph(kind: .heading(1), runs: [InlineRun(text: "ab")]),
            Paragraph(kind: .list(.ordered, 2), runs: [InlineRun(text: "cd")])])
        bridge.load(source)
        bridge.select(NSRange(location: 1, length: 3))
        view.setMarkedText("候选", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 1, length: 3))
        view.insertText("提交", replacementRange: view.markedRange())
        XCTAssertEqual(view.string, "a提交d")
        view.undo(nil)
        XCTAssertEqual(bridge.document.paragraphs, source.paragraphs)
        assertProjection()
    }

    func testImageOnlyListAndMixedCutRoundTrip_M06_M10_P11_D07() throws {
        let image = NSImage(size: NSSize(width: 30, height: 80))
        image.lockFocus(); NSColor.orange.setFill(); NSRect(x: 0, y: 0, width: 30, height: 80).fill(); image.unlockFocus()
        bridge.execute(.list(.ordered)); view.insertTab(nil)
        bridge.insertImages([image]); view.insertNewline(nil)
        XCTAssertEqual(bridge.document.paragraphs.map(\.kind), [.list(.ordered, 2), .list(.ordered, 2)])
        XCTAssertFalse(bridge.document.paragraphs[0].isEmpty)
        XCTAssertTrue(bridge.document.paragraphs[1].isEmpty)
        view.insertNewline(nil) // Keep a lower-depth empty item in the copied fragment.
        let source = bridge.document
        bridge.select(NSRange(location: 0, length: source.length))
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        bridge.copy(to: board, cut: true)
        XCTAssertTrue(bridge.document.assetOrder.isEmpty)
        view.undo(nil)
        XCTAssertEqual(bridge.document.paragraphs, source.paragraphs)
        XCTAssertEqual(bridge.document.assets, source.assets)
        view.redo(nil)
        bridge.paste(from: board)
        XCTAssertEqual(bridge.document.text, source.text)
        XCTAssertEqual(bridge.document.paragraphs.map(\.kind), source.paragraphs.map(\.kind))
        XCTAssertEqual(bridge.document.assetOrder.count, 1)
        XCTAssertEqual(try XCTUnwrap(bridge.document.assets[bridge.document.assetOrder[0]]).data,
                       try XCTUnwrap(source.assets[source.assetOrder[0]]).data)
        let export = HTMLExporter.export(bridge.document)
        XCTAssertEqual(export.assetIDs, bridge.document.assetOrder)
        XCTAssertFalse(export.bodyHTML.contains("\u{FFFC}"))
        var repeated = bridge.document
        let id = repeated.assetOrder[0]
        repeated.paragraphs[1].runs = [.image(id)]
        XCTAssertEqual(HTMLExporter.export(repeated).assetIDs, [id, id])
        XCTAssertFalse(HTMLExporter.export(repeated).bodyHTML.contains("\u{FFFC}"))
        assertProjection()
        bridge.load(EditorDocument())
        XCTAssertTrue(bridge.document.assets.isEmpty)
        XCTAssertFalse(bridge.history.manager.canUndo)
    }

    func testReturnScrollsToTrailingEmptyLineWithoutFurtherTyping() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120), styleMask: [], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        scroll.hasVerticalScroller = true
        window.contentView = scroll; scroll.documentView = view
        defer { scroll.documentView = nil; window.contentView = nil }
        for prefix in ["", "- ", "1. "] {
            bridge.load(EditorDocument()); type(prefix)
            for _ in 0..<25 { type("line"); view.insertNewline(nil) }
            // Capture the viewport before a geometry query can finish deferred layout.
            let visible = view.visibleRect
            let height = view.frame.height
            let offset = scroll.contentView.bounds.minY
            view.layoutManager!.ensureLayout(for: view.textContainer!)
            let lastLine = view.layoutManager!.extraLineFragmentRect.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
            XCTAssertFalse(lastLine.isEmpty)
            XCTAssertGreaterThan(offset, 0)
            XCTAssertGreaterThanOrEqual(height, lastLine.maxY)
            XCTAssertLessThanOrEqual(lastLine.maxY, visible.maxY + 1)
            XCTAssertGreaterThanOrEqual(lastLine.minY, visible.minY - 1)
        }
    }

    func testEightLevelListsAndClipboardRoundTrip() throws {
        let expected = ["●", "○", "◆", "◇", "■", "□", "▲", "△"]
        for kind in [ListKind.unordered, .ordered] {
            let source = EditorDocument(paragraphs: (1...8).map {
                Paragraph(kind: .list(kind, $0), runs: [InlineRun(text: "level \($0)")])
            })
            XCTAssertNoThrow(try source.validated())
            bridge.load(source)
            for i in 0..<8 {
                XCTAssertEqual(bridge.listItems[i]?.marker, kind == .unordered ? expected[i] : "1.")
                XCTAssertEqual(TextKitRenderer.paragraphStyle(source.paragraphs[i].kind).headIndent, CGFloat((i + 1) * 22))
            }
            let rich = TextKitRenderer.render(source, exchange: true)
            let data = try XCTUnwrap(rich.rtfd(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]))
            let decoded = try XCTUnwrap(NSAttributedString(rtfd: data, documentAttributes: nil))
            XCTAssertEqual(ClipboardCodec.importRich(decoded).paragraphs.map(\.kind), source.paragraphs.map(\.kind))
            let tag = kind == .ordered ? "ol" : "ul"
            XCTAssertEqual(HTMLExporter.export(source).bodyHTML.components(separatedBy: "<\(tag)>").count - 1, 8)
        }
        let style = NSMutableParagraphStyle()
        style.textLists = (0..<10).map { _ in NSTextList(markerFormat: .disc, options: 0) }
        let imported = ClipboardCodec.importRich(NSAttributedString(string: "deep", attributes: [.paragraphStyle: style]))
        XCTAssertEqual(imported.paragraphs[0].kind, .list(.unordered, 8))
        XCTAssertThrowsError(try EditorDocument(paragraphs: [Paragraph(kind: .list(.ordered, 9))]).validated())
    }

    func testHeadingPrefixIsConsumedBeforeTextAndComposition() {
        for prefix in ["# ", "## ", "### "] {
            bridge.load(EditorDocument()); type(prefix)
            XCTAssertEqual(view.string, "")
            XCTAssertEqual(bridge.document.text, "")
            view.setMarkedText("biaoti", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            view.insertText("标题", replacementRange: view.markedRange())
            XCTAssertEqual(view.string, "标题")
            XCTAssertEqual(bridge.document.paragraphs[0].kind, .heading(prefix.count - 1))
            assertProjection()
        }
    }

    func testEmptyMarkedTextDoesNotLeaveFormattingDisabled() {
        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertFalse(bridge.isComposing)
        XCTAssertTrue(bridge.history.manager.isUndoRegistrationEnabled)
        bridge.execute(.toggle(.bold))
        XCTAssertTrue(bridge.state.session.insertionStyle.marks.contains(.bold))
    }

    func testCancellingMarkedTextRestoresFormattingAndUndo() {
        type("before")
        let before = bridge.document
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(bridge.isComposing)
        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: view.markedRange())
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertFalse(bridge.isComposing)
        XCTAssertEqual(bridge.document.paragraphs, before.paragraphs)
        XCTAssertTrue(bridge.history.manager.isUndoRegistrationEnabled)
        bridge.execute(.list(.ordered))
        XCTAssertEqual(bridge.document.paragraphs[0].kind, .list(.ordered, 1))
        view.undo(nil)
        XCTAssertEqual(bridge.document.paragraphs, before.paragraphs)
    }

    func testFirstMarkedCharacterNeverUsesStaleEmptyListPreview() {
        for prefix in ["- ", "1. "] {
            bridge.load(EditorDocument()); type(prefix + "first"); view.insertNewline(nil)
            bridge.beginComposition()
            XCTAssertTrue(bridge.presentationDocument.paragraphs[1].isEmpty) // Prime the empty-line preview.
            var observedDuringNativeEdit = false
            let token = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification,
                object: view.textStorage, queue: nil) { [self] _ in
                guard view.string.hasSuffix("zhong") else { return }
                observedDuringNativeEdit = true
                let preview = bridge.presentation
                XCTAssertEqual(preview.document.text, view.string)
                XCTAssertEqual(preview.positions.length, (view.string as NSString).length)
                XCTAssertNotNil(preview.lists[1])
                XCTAssertFalse(preview.document.paragraphs[1].isEmpty)
            }
            view.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            NotificationCenter.default.removeObserver(token)
            XCTAssertTrue(observedDuringNativeEdit)
            let preview = bridge.presentation
            let geometry = ListMarkerRenderer.firstLine(1, document: preview.document, map: preview.positions, view: view)
            XCTAssertNotNil(geometry)
            XCTAssertFalse(geometry!.0.isEmpty)
            view.insertText("中", replacementRange: view.markedRange())
            XCTAssertNotNil(bridge.listItems[1])
            XCTAssertEqual(bridge.document.paragraphs[1].text, "中")
        }
    }
}
