import AppKit
import XCTest
@testable import NotesMateEditor

final class EditorTipsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var clock: TimeInterval = 0
    private var jobs: [(TimeInterval, DispatchWorkItem)] = []
    override func setUp() {
        suite = "NotesMate.tips.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    private func pump(_ interval: TimeInterval = 0) {
        let end = clock + interval
        while let next = jobs.enumerated().filter({ $0.element.0 <= end }).min(by: { $0.element.0 < $1.element.0 }) {
            let job = jobs.remove(at: next.offset)
            clock = job.0; job.1.perform()
        }
        clock = end
    }
    private func controller() -> EditorTipsController {
        let tips = EditorTipsController(history: EditorTipHistory(defaults: defaults),
            timing: .init(hover: 0.015),
            enqueue: { [unowned self] delay, work in self.jobs.append((self.clock + delay, work)) })
        tips.canPresent = { _ in true }; tips.canSave = { true }
        return tips
    }
    private func model(_ document: EditorDocument, tips: EditorTipsController, activate: Bool = true) -> (NoteEditorModel, EditorTextView) {
        let model = NoteEditorModel(drafts: DraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)), restore: false, tips: tips)
        let view = EditorTextView.make(); model.bridge.attach(view); model.bridge.load(document)
        tips.canPresent = { [weak model] _ in model?.isComposing == false }
        if activate { tips.activate() }
        addTeardownBlock { model.flushPendingPersist(); try? FileManager.default.removeItem(at: model.drafts.directory) }
        return (model, view)
    }
    private func commandA(_ view: EditorTextView, repeatKey: Bool = false) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: repeatKey, keyCode: 0)!
        XCTAssertTrue(view.performKeyEquivalent(with: event))
    }

    func testEachFeatureOncePerLaunchAndReopeningDoesNotResetAllowance() {
        defaults.set(999, forKey: "tips.dailyCount")
        defaults.set(999, forKey: "tips.count.code.exit")
        defaults.set(Date(), forKey: "tips.last")
        let tips = controller()
        tips.activate(); tips.showFeature(.codeExit); tips.showFeature(.indent); pump()
        XCTAssertEqual(tips.visible, .codeExit)
        pump(3); XCTAssertEqual(tips.visible, .indent)
        pump(3); XCTAssertNil(tips.visible)
        for _ in 0..<5 {
            tips.endSession(); tips.activate()
            tips.showFeature(.codeExit); tips.showFeature(.indent); pump()
            XCTAssertNil(tips.visible)
        }
        tips.showFeature(.selectAll); pump()
        XCTAssertEqual(tips.visible, .selectAll, "Another feature has its own allowance")
        tips.endSession()
        let relaunched = controller() // Same defaults, new application-owned controller.
        relaunched.activate(); relaunched.showFeature(.codeExit); pump()
        XCTAssertEqual(relaunched.visible, .codeExit)
    }

    func testInitialNoticePrecedesDraftTeachingAndDoesNotReplayOnReopen() {
        let tips = controller()
        tips.onSessionBegan = { [weak tips] in tips?.showFeature(.heading) }
        tips.beginSession(initialMessage: "欢迎使用 NotesMate")
        tips.activate(); pump()
        XCTAssertEqual(tips.visible?.message, "欢迎使用 NotesMate")
        XCTAssertEqual(tips.visible?.icon, "info.circle")
        pump(2.99); XCTAssertEqual(tips.visible?.id, "info.session.initial")
        pump(0.02); XCTAssertEqual(tips.visible, .heading)
        tips.endSession(); tips.activate(); pump()
        XCTAssertNil(tips.visible)
    }
    func testClosingDoesNotLearnButLearningPersistsAcrossLaunches() {
        defaults.set(true, forKey: "tips.learned.code.exit")
        let tips = controller(); tips.activate(); tips.showFeature(.codeExit); pump()
        tips.dismissCurrent()
        XCTAssertFalse(tips.history.isLearned(.codeExit))
        tips.endSession(); tips.activate(); tips.showFeature(.codeExit); pump()
        XCTAssertNil(tips.visible, "Dismissing still consumes this launch's allowance")
        let relaunched = controller()
        relaunched.activate(); relaunched.showFeature(.codeExit); pump()
        XCTAssertEqual(relaunched.visible, .codeExit)
        relaunched.learned(.codeExit)
        XCTAssertEqual(relaunched.visible, .codeExit, "Learning preserves current reading time")
        relaunched.endSession()
        let nextLaunch = controller()
        nextLaunch.activate(); nextLaunch.showFeature(.codeExit); pump()
        XCTAssertNil(nextLaunch.visible)
        XCTAssertTrue(EditorTipHistory(defaults: defaults).isLearned(.codeExit))
    }
    func testInformationBypassesFeatureSettingsAndHasDistinctIconAndDuration() {
        defaults.set(false, forKey: EditorTipHistory.enabledKey)
        let tips = controller(); tips.activate(); tips.showFeature(.indent)
        tips.showInformation(id: "notice", message: "目标目录已更新", duration: .short); pump()
        XCTAssertEqual(tips.visible?.icon, "info.circle")
        XCTAssertEqual(EditorTip.codeExit.icon, "lightbulb")
        pump(0.5); tips.showInformation(id: "notice", message: "目标目录已更新", duration: .long)
        pump(1.01); XCTAssertNil(tips.visible, "Duplicate notices must not extend the deadline")
        tips.showInformation(id: "notice", message: "再次更新"); pump()
        XCTAssertNotNil(tips.visible)
        XCTAssertFalse(tips.history.isLearned(.information(id: "notice", message: "再次更新")))
    }
    func testShortMediumAndLongDurationPresets() {
        let tips = controller(); tips.activate()
        for (index, preset, seconds) in [
            (0, EditorTipsController.DisplayDuration.short, 1.5),
            (1, .medium, 3.0),
            (2, .long, 5.0),
        ] {
            tips.showInformation(id: "preset.\(index)", message: "提示", duration: preset)
            pump()
            XCTAssertNotNil(tips.visible)
            pump(seconds - 0.01)
            XCTAssertNotNil(tips.visible, "\(preset) ended early")
            pump(0.02)
            XCTAssertNil(tips.visible, "\(preset) did not expire")
        }
    }
    func testInformationNoticeAppearsDuringSaveHoverAndUsesDefaultMediumDuration() {
        let tips = controller()
        tips.activate()
        tips.saveHover(true)
        tips.setBlocked(true)
        tips.showInformation(id: "permission", message: "授权提示")
        tips.setBlocked(false)
        pump()
        XCTAssertEqual(tips.visible?.message, "授权提示")
        pump(2.99)
        XCTAssertNotNil(tips.visible)
        pump(0.02)
        XCTAssertNil(tips.visible)
    }
    func testFIFOAndLearningWhileQueuedAndCloseCancelsOldCallbacks() {
        let tips = controller(); tips.activate()
        tips.showFeature(.codeExit); tips.showFeature(.indent); tips.showFeature(.selectAll); pump()
        XCTAssertEqual(tips.visible, .codeExit)
        tips.learned(.indent); pump(3)
        XCTAssertEqual(tips.visible, .selectAll)
        tips.endSession(); tips.activate(); tips.showInformation(id: "new", message: "新提示"); pump()
        pump(2.9); XCTAssertEqual(tips.visible?.id, "info.new")
        pump(0.11); XCTAssertNil(tips.visible)
    }
    func testSaveHoverPriorityAndOldExpiryCannotDismissNewNotice() {
        let tips = controller(); tips.activate(); tips.showFeature(.codeExit); pump()
        pump(1); tips.saveHover(true); pump(0.02)
        XCTAssertEqual(tips.visible, .save)
        pump(1.1); XCTAssertEqual(tips.visible, .save)
        pump(1); XCTAssertEqual(tips.visible, .save, "The old feature expiry must not dismiss the save hint")
        pump(1); XCTAssertNil(tips.visible)
        tips.saveHover(true); pump(0.02); XCTAssertNil(tips.visible)
        tips.saveHover(false); tips.saveHover(true); tips.saveHover(false); pump(0.02)
        XCTAssertNil(tips.visible)
        tips.saveHover(true); pump(0.02); XCTAssertEqual(tips.visible, .save)
        tips.editingActivity(); XCTAssertNil(tips.visible)
    }
    func testNestedMenusDelayNewRequestsAndCompositionWaitsForCommit() {
        let tips = controller(); tips.activate(); tips.menuTracking(true); tips.menuTracking(true)
        tips.showFeature(.codeExit); tips.menuTracking(false); pump(); XCTAssertNil(tips.visible)
        tips.menuTracking(false); pump(); XCTAssertEqual(tips.visible, .codeExit)
        tips.dismissCurrent()
        var composing = true
        tips.canPresent = { _ in !composing }
        tips.showFeature(.indent); pump(); XCTAssertNil(tips.visible)
        composing = false; tips.editorChanged(); pump(); XCTAssertEqual(tips.visible, .indent)
        tips.endSession(); tips.activate(); pump(); XCTAssertNil(tips.visible)
    }
    func testCodeEnterTriggersImmediatelyAndOnlyDownExitLearns() {
        let tips = controller()
        let (model, view) = model(.plain("正文"), tips: tips)
        model.setBlock(.codeLine); pump()
        XCTAssertEqual(tips.visible, .codeExit)
        model.bridge.withKeyPress(EditorKey(code: 125)) {} // An earlier Down must not leak into a menu action.
        model.setBlock(.body)
        XCTAssertFalse(tips.history.isLearned(.codeExit))
        model.setBlock(.codeLine)
        model.bridge.select(NSRange(location: model.bridge.document.length, length: 0))
        model.bridge.withKeyPress(EditorKey(code: 125)) { view.moveDown(nil) }
        XCTAssertTrue(tips.history.isLearned(.codeExit))
        XCTAssertEqual(tips.visible, .codeExit)
        XCTAssertNil(model.bridge.hookContext.key)
    }
    func testMediumReadingTimeSurvivesInputIMESelectionAndLearning() {
        let tips = controller()
        let (model, view) = model(EditorDocument(paragraphs: [Paragraph(kind: .codeLine)]), tips: tips)
        model.setBlock(.body); model.setBlock(.codeLine)
        pump(); XCTAssertEqual(tips.visible, .codeExit)
        for ch in "let x = 1" {
            tips.editingActivity()
            view.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0))
            tips.editingActivity(clearStatus: false); pump(0.1)
            XCTAssertEqual(tips.visible, .codeExit)
        }
        view.insertNewline(nil)
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(model.isComposing); XCTAssertEqual(tips.visible, .codeExit)
        view.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0)); view.unmarkText()
        model.bridge.select(NSRange(location: model.bridge.document.length, length: 0))
        model.bridge.withKeyPress(EditorKey(code: 125)) { view.moveDown(nil) }
        XCTAssertTrue(tips.history.isLearned(.codeExit))
        pump(2.99 - clock); XCTAssertEqual(tips.visible, .codeExit)
        pump(0.02); XCTAssertNil(tips.visible)
        XCTAssertEqual(model.bridge.document.text, view.string)
    }
    func testCmdAFirstPressShowsAndConsecutiveSecondLearns() {
        let tips = controller()
        let (model, view) = model(.plain("第一段\n第二段\n第三段"), tips: tips)
        commandA(view); pump()
        XCTAssertEqual(tips.visible, .selectAll)
        XCTAssertEqual(model.bridge.hookContext.selectionStage, 1)
        model.bridge.keyReleased(EditorKey(code: 0, modifiers: .command))
        commandA(view)
        XCTAssertEqual(model.bridge.hookContext.selectionStage, 2)
        XCTAssertTrue(tips.history.isLearned(.selectAll))
        XCTAssertEqual(tips.visible, .selectAll)
    }
    func testFastCmdALearnsBeforeQueuedTipAndSingleScopeNeverTeaches() {
        let tips = controller()
        let (model, view) = model(.plain("one\ntwo"), tips: tips)
        commandA(view); commandA(view); pump()
        XCTAssertTrue(tips.history.isLearned(.selectAll)); XCTAssertNil(tips.visible)
        let other = controller()
        let (_, singleView) = self.model(.plain("only"), tips: other)
        commandA(singleView); pump(); XCTAssertNil(other.visible)
        XCTAssertEqual(model.bridge.document.text, "one\ntwo")
    }
    func testCmdALearningUsesResultInsteadOfPreviousKeyHistory() {
        for interruption in ["pointer", "key", "repeat"] {
            defaults.removeObject(forKey: "tips.v3.learned.selection.expand")
            let tips = controller()
            let (model, view) = model(.plain("one\ntwo\nthree"), tips: tips)
            commandA(view)
            // Notifications alone do not change the editor's valid selection result.
            switch interruption {
            case "pointer": model.bridge.hooks.emit(.pointerPress, context: model.bridge.hookContext)
            case "key": model.bridge.withKeyPress(EditorKey(code: 123)) {}
            default: break
            }
            commandA(view, repeatKey: interruption == "repeat")
            XCTAssertEqual(model.bridge.hookContext.selectionStage, 2)
            XCTAssertEqual(tips.history.isLearned(.selectAll), interruption != "repeat", interruption)
        }
    }

    func testActualSelectionChangeResetsResultBeforeNextCmdA() {
        let tips = controller()
        let (model, view) = model(.plain("one\ntwo\nthree"), tips: tips)
        commandA(view)
        model.bridge.select(NSRange(location: 4, length: 0))
        commandA(view); pump()
        XCTAssertEqual(model.bridge.hookContext.selectionStage, 1)
        XCTAssertFalse(tips.history.isLearned(.selectAll))
        XCTAssertEqual(tips.visible, .selectAll)
        commandA(view)
        XCTAssertTrue(tips.history.isLearned(.selectAll))
    }

    func testCmdALearnsFromExistingScopeWithoutObservingFirstKey() {
        let tips = controller()
        let (model, view) = model(.plain("one\ntwo"), tips: tips)
        view.selectAll(nil) // Menu action establishes a first-stage selection without a Cmd+A hook.
        pump(); XCTAssertNil(tips.visible)
        XCTAssertEqual(model.bridge.hookContext.selectionStage, 1)
        commandA(view); pump()
        XCTAssertEqual(model.bridge.hookContext.selectionStage, 2)
        XCTAssertTrue(tips.history.isLearned(.selectAll))
        XCTAssertNil(tips.visible)
    }

    func testCmdAWithoutSelectionResultDoesNotTeachOrLearn() {
        let tips = controller()
        let (model, _) = model(.plain("one\ntwo"), tips: tips)
        model.bridge.withKeyPress(EditorKey(code: 0, modifiers: .command)) {}
        pump()
        XCTAssertEqual(model.bridge.hookContext.selectionStage, 0)
        XCTAssertFalse(tips.history.isLearned(.selectAll))
        XCTAssertNil(tips.visible)
    }
    func testInputAndFormatHooksHaveScopedKeyContextAndCanUnsubscribe() {
        let bridge = AppKitInputBridge(); let view = EditorTextView.make(); bridge.attach(view)
        var before = 0, after = 0, enters = 0, leaves = 0, releases = 0
        let token = bridge.hooks.observe { hook, context in
            switch hook {
            case .beforeInput: before += 1
            case .afterInput: after += 1
            case .enterFormat(.codeLine): enters += 1
            case .leaveFormat(.codeLine): leaves += 1; XCTAssertEqual(context.key?.code, 125)
            case .keyRelease: releases += 1
            default: break
            }
        }
        bridge.execute(.block(.codeLine))
        bridge.withKeyPress(EditorKey(code: 0)) { view.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        bridge.withKeyPress(EditorKey(code: 125)) { view.moveDown(nil) }
        bridge.keyReleased(EditorKey(code: 125))
        XCTAssertEqual(enters, 1); XCTAssertEqual(leaves, 1); XCTAssertEqual(releases, 1)
        XCTAssertEqual(before, after); XCTAssertGreaterThanOrEqual(after, 3)
        XCTAssertNil(bridge.hookContext.key)
        bridge.hooks.removeObserver(token); bridge.execute(.block(.codeLine))
        XCTAssertEqual(enters, 1)
    }
    func testGeometrySupportsSelectionAndBothNoticeKindsAtWideAndNarrowWidths() {
        for width: CGFloat in [360, 380, 900] {
            for tip in [EditorTip.codeExit, .selectAll, .information(id: "test", message: "普通提示")] {
                let rect = EditorTipContext.frame(for: tip, in: CGSize(width: width, height: 300))!
                XCTAssertEqual(rect.width, 300); XCTAssertEqual(rect.minY, 8); XCTAssertEqual(rect.midX, width / 2)
            }
        }
        XCTAssertNil(EditorTipContext.frame(for: .indent, in: CGSize(width: 180, height: 40)))
    }

    func testListThreeStageSelectionLearnsAtSecondStage() {
        let tips = controller()
        tips.learned(.indent)
        let document = EditorDocument(paragraphs: [
            Paragraph(runs: [InlineRun(text: "before")]),
            Paragraph(kind: .list(.unordered, 1), runs: [InlineRun(text: "parent")]),
            Paragraph(kind: .list(.unordered, 2), runs: [InlineRun(text: "child")]),
            Paragraph(runs: [InlineRun(text: "after")])
        ])
        let (model, view) = model(document, tips: tips)
        model.bridge.select(NSRange(location: PositionMap(document).range(of: 2).location, length: 0))
        commandA(view); pump()
        XCTAssertEqual(model.bridge.hookContext.selectionStageCount, 3)
        XCTAssertEqual(tips.visible, .selectAll)
        XCTAssertFalse(tips.history.isLearned(.selectAll))
        commandA(view)
        XCTAssertEqual(model.bridge.hookContext.selectionStage, 2)
        XCTAssertTrue(tips.history.isLearned(.selectAll))
        commandA(view)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: document.length))
        XCTAssertEqual(model.bridge.document.text, document.text)
    }

    func testHeadingAndIndentLearnOnlyAfterSuccessfulKeyboardOperation() {
        let tips = controller()
        let (model, view) = model(.plain("#"), tips: tips)
        model.bridge.select(NSRange(location: 1, length: 0))
        model.bridge.withKeyPress(EditorKey(code: 49)) {
            view.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        XCTAssertEqual(model.bridge.hookContext.format, .heading(1))
        XCTAssertTrue(tips.history.isLearned(.heading))
        pump()
        XCTAssertNil(tips.visible, "Successful heading syntax learns before the queued tip can flash")
        model.setBlock(.list(.ordered, 8))
        model.bridge.withKeyPress(EditorKey(code: 48)) { view.insertTab(nil) }
        XCTAssertFalse(tips.history.isLearned(.indent), "A no-op at maximum depth is not learning")
        model.bridge.withKeyPress(EditorKey(code: 48, modifiers: .shift)) { view.insertBacktab(nil) }
        XCTAssertEqual(model.bridge.hookContext.format, .list(.ordered, 7))
        XCTAssertTrue(tips.history.isLearned(.indent))
    }

    func testCodeMovementWithinBlockDoesNotLearnAndMouseReleaseCanDrain() {
        let tips = controller()
        let (model, view) = model(EditorDocument(paragraphs: [
            Paragraph(kind: .codeLine, runs: [InlineRun(text: "one")]),
            Paragraph(kind: .codeLine, runs: [InlineRun(text: "two")])
        ]), tips: tips)
        var mouseHeld = true
        tips.canPresent = { _ in !mouseHeld }
        model.setBlock(.body); model.setBlock(.codeLine)
        pump(); XCTAssertNil(tips.visible)
        mouseHeld = false; tips.editorChanged(); pump()
        XCTAssertEqual(tips.visible, .codeExit)
        model.bridge.withKeyPress(EditorKey(code: 125)) { view.moveDown(nil) }
        XCTAssertEqual(model.bridge.hookContext.format, .codeLine)
        XCTAssertFalse(tips.history.isLearned(.codeExit))
    }

    func testShortcutKeyUsesLayoutCharactersAndIgnoresCapsLock() {
        XCTAssertTrue(EditorKey(code: 12, modifiers: [.command, .capsLock], characters: "A").isSelectAll)
        XCTAssertFalse(EditorKey(code: 0, modifiers: .command, characters: "q").isSelectAll)
        XCTAssertFalse(EditorKey(code: 0, modifiers: [.command, .shift], characters: "a").isSelectAll)
    }

    func testReopeningPreservesAllowanceWithoutSynthesizingFormatEntry() {
        for kind in [BlockKind.list(.unordered, 1), .list(.ordered, 1), .codeLine, .heading(1)] {
            let tips = controller()
            let document = EditorDocument(paragraphs: [
                Paragraph(runs: [InlineRun(text: "body")]),
                Paragraph(kind: kind, runs: [InlineRun(text: "formatted")])
            ])
            let (model, _) = model(document, tips: tips)
            let body = NSRange(location: 0, length: 0)
            let formatted = NSRange(location: PositionMap(document).range(of: 1).location, length: 0)
            var enters = 0
            model.bridge.hooks.observe { hook, _ in
                if case .enterFormat = hook { enters += 1 }
            }
            model.bridge.select(formatted); pump()
            let expected: EditorTip? = kind.isCode ? .codeExit : kind.list != nil ? .indent : nil
            XCTAssertEqual(tips.visible, expected)
            for _ in 0..<3 {
                tips.endSession()
                let previousEnters = enters
                tips.activate(); pump()
                XCTAssertNil(tips.visible, "Reopening on a formatted line is not entering a format")
                XCTAssertEqual(enters, previousEnters)
                model.bridge.select(formatted); pump()
                XCTAssertNil(tips.visible, "Restoring focus/selection must not trigger entry either")
                model.bridge.select(body); model.bridge.select(formatted); pump()
                XCTAssertNil(tips.visible, "Real re-entry cannot reset the application launch allowance")
                tips.dismissCurrent()
                model.bridge.select(body); model.bridge.select(formatted); pump()
                XCTAssertNil(tips.visible, "Still only once per feature in the same application launch")
            }
        }
    }

    func testDraftCreationTeachesOnceEvenWhenEmptyDraftIsReopened() {
        let tips = controller()
        let (model, _) = model(EditorDocument(), tips: tips, activate: false)
        var created = 0
        model.bridge.hooks.observe { hook, _ in
            if case .draftCreated = hook { created += 1 }
        }
        XCTAssertEqual(created, 0)
        tips.activate(); pump()
        XCTAssertEqual(created, 1)
        XCTAssertEqual(tips.visible, .heading)
        tips.dismissCurrent()
        for _ in 0..<3 {
            tips.endSession(); tips.activate(); pump()
            XCTAssertEqual(created, 1)
            XCTAssertNil(tips.visible, "An existing empty draft must survive window reopen")
        }
        model.setBlock(.heading(1)); model.setBlock(.body); pump()
        XCTAssertNil(tips.visible, "Formatting does not create another draft")
        XCTAssertEqual(created, 1)
    }

    func testDeletingAllContentDoesNotCreateAnotherDraft() {
        let tips = controller()
        let (model, view) = model(EditorDocument(), tips: tips)
        pump(); tips.dismissCurrent()
        var created = 0
        model.bridge.hooks.observe { hook, _ in
            if case .draftCreated = hook { created += 1 }
        }
        view.insertText("text", replacementRange: NSRange(location: NSNotFound, length: 0))
        model.bridge.select(NSRange(location: 0, length: model.bridge.document.length))
        view.deleteBackward(nil)
        XCTAssertTrue(model.bridge.document.isPristine)
        tips.endSession(); tips.activate(); pump()
        XCTAssertEqual(created, 0)
        XCTAssertNil(tips.visible)
    }

    func testRestoredDraftDoesNotFireCreation() throws {
        for empty in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let store = DraftStore(directory: directory)
            var session = EditorSession()
            session.insertionStyle.marks = .bold
            store.persist(empty ? EditorDocument() : .plain("restored"), session: session)
            store.flush()
            let tips = controller()
            let model = NoteEditorModel(drafts: store, tips: tips)
            tips.canPresent = { _ in true }
            var created = 0
            model.bridge.hooks.observe { hook, _ in
                if case .draftCreated = hook { created += 1 }
            }
            for _ in 0..<3 {
                tips.activate(); pump()
                XCTAssertEqual(created, 0)
                XCTAssertNil(tips.visible)
                tips.endSession()
            }
            model.flushPendingPersist()
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testSuccessfulSaveCreatesNextDraftButFailureDoesNot() {
        let tips = controller()
        let (model, _) = model(.plain("note"), tips: tips)
        var created = 0
        model.bridge.hooks.observe { hook, _ in
            if case .draftCreated = hook { created += 1 }
        }
        XCTAssertEqual(model.save(using: { _ in .failed("test") }), .failed("test"))
        pump(); XCTAssertEqual(created, 0); XCTAssertNil(tips.visible)
        tips.setBlocked(true)
        XCTAssertEqual(model.save(using: { _ in .success }), .success)
        pump(); XCTAssertEqual(created, 1); XCTAssertNil(tips.visible)
        XCTAssertTrue(model.isEmpty)
        tips.setBlocked(false); pump()
        XCTAssertEqual(tips.visible, .heading)
        model.bridge.load(.plain("another note"))
        XCTAssertEqual(model.save(using: { _ in .success }), .success)
        XCTAssertEqual(created, 2)
        pump(3.1); XCTAssertNil(tips.visible, "Creation does not bypass the once-per-launch feature limit")
        tips.endSession(); tips.activate(); pump()
        XCTAssertEqual(created, 2); XCTAssertNil(tips.visible)
    }

    func testLearnedHeadingStaysSilentForNewDrafts() {
        let tips = controller()
        let (model, view) = model(EditorDocument(), tips: tips)
        view.insertText("#", replacementRange: NSRange(location: NSNotFound, length: 0))
        model.bridge.withKeyPress(EditorKey(code: 49)) {
            view.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        pump()
        XCTAssertTrue(tips.history.isLearned(.heading))
        XCTAssertNil(tips.visible)
        tips.endSession(); tips.activate()
        model.clear(); pump()
        XCTAssertNil(tips.visible, "A real new draft still respects learned history")
    }

    func testHeadingLearningUsesSyntaxResultNotCurrentFormat() {
        let tips = controller()
        let (model, view) = model(.plain("title"), tips: tips)
        model.setBlock(.heading(1))
        model.bridge.select(NSRange(location: model.bridge.document.length, length: 0))
        model.bridge.withKeyPress(EditorKey(code: 49)) {
            view.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        XCTAssertFalse(tips.history.isLearned(.heading), "A space in a toolbar-created heading is not syntax usage")
        model.bridge.load(.plain("#"))
        model.bridge.select(NSRange(location: 1, length: 0))
        // A real shortcut conversion is sufficient, even without a physical-key hook.
        view.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(tips.history.isLearned(.heading))
    }
}
