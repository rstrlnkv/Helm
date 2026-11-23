import HelmRuntime
import HelmUI
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The edit mode and its removal with what nobody fed them: a hold whose tile goes, whose button is no longer down, whose grid is regridded under it;
/// a badge press dragged off; two asks racing; a card for an app that is gone; a window that closes while the Uninstaller is still counting.
@MainActor final class TheEditModeSurvivesTheInputsNobodyFedTests: XCTestCase {
    /// A preview that stays in the door until the test lets it out, one answer per ask, in the order asked.
    @MainActor final class Gate {
        private var waiting: [CheckedContinuation<AppRemovalPreview?, Never>] = []
        private(set) var asked: [String] = []
        func preview(_ candidate: AppRemovalCandidate) async -> AppRemovalPreview? {
            asked.append(candidate.bundleID)
            return await withCheckedContinuation { waiting.append($0) }
        }
        func release(_ index: Int, _ answer: AppRemovalPreview?) { waiting[index].resume(returning: answer) }
        static let counted = AppRemovalPreview(appBytes: 10, leftoverCount: 0, leftoverBytes: 0, running: false)
    }

    private func rig(_ ids: [String] = ["a", "b", "c", "d"]) async -> LiftRig {
        let r = LiftRig(self, apps: ids)
        r.state.onVerdicts = { candidates in candidates.map { _ in .removable } }
        r.state.beginEditing()
        await waitUntil("the verdicts") { r.state.removable == Set(ids) }
        return r
    }

    private func without(_ r: LiftRig, _ gone: String) {
        r.catalog.reading = CatalogReading(apps: r.catalog.reading.apps.filter { $0.id != gone }, complete: true)
        r.state.update(snapshot: r.engine.read(reason: .refresh))
    }

    private func settle() async { for _ in 0..<30 { await Task.yield() } }

    // MARK: The hold

    func testTheHeldTileVanishingUnderTheHoldLiftsNobodyAndLeavesNothingPressed() {
        let r = LiftRig(self, apps: ["a", "b", "c", "d"])
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 0))
        without(r, "a")
        r.state.tick(at: 0.5)
        r.state.pointerMoved(CGPoint(x: r.core(0).x + 20, y: r.core(0).y), time: 0.6)
        XCTAssertNil(r.state.lift, "the tile now at that address (b) is not the one that was held")
        XCTAssertFalse(r.state.pointerBusy)
        XCTAssertNil(r.state.pressedID)
        XCTAssertEqual(r.placed.count, 0)
        r.state.pointerUp(r.core(0), time: 0.7)
        XCTAssertEqual(r.launched, [])
        XCTAssertTrue(r.state.pointerDown(r.core(1), time: 1), "the window takes the next press")
    }

    func testAHoldWhoseButtonIsNoLongerDownEndsCleanlyAndKeepsTheMode() {
        let r = LiftRig(self, apps: ["a", "b"])
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 0))
        r.state.tick(at: 0.5)
        XCTAssertTrue(r.state.editing)
        r.state.buttonDown = { false }
        r.state.tick(at: 1.0)
        XCTAssertFalse(r.state.pointerBusy, "the mouse-up that never came")
        XCTAssertNil(r.state.pressedID)
        XCTAssertTrue(r.state.editing)
        XCTAssertEqual(r.launched, [])
    }

    func testARegridUnderAHoldCancelsThePressAndTheNextPressIsTaken() {
        let r = LiftRig(self, apps: ["a", "b", "c"])
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 0))
        var settings = LaunchpadGridSettings.standard
        settings.sizeMultiplier = 1.2
        r.state.regrid(settings)
        XCTAssertFalse(r.state.pointerBusy)
        XCTAssertNil(r.state.pressedID)
        r.state.tick(at: 0.5)
        XCTAssertFalse(r.state.editing, "the press was cancelled: no mode out of it")
    }

    func testAKeyOrASearchBeforeTheHoldIsDueBeginsNoMode() {
        let r = LiftRig(self, apps: ["a", "b"])
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 0))
        r.state.search = "a"
        r.state.tick(at: 0.5)
        XCTAssertFalse(r.state.editing, "a search is on: no mode")
        r.state.pointerUp(r.core(0), time: 0.6)
        XCTAssertFalse(r.state.pointerBusy)
    }

    func testASecondPressWhileOneIsHeldIsLeftAloneAndTheHoldStillBegins() {
        let r = LiftRig(self, apps: ["a", "b"])
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 0))
        XCTAssertFalse(r.state.pointerDown(r.core(1), time: 0.1), "the second finger of a two-finger press")
        r.state.tick(at: 0.5)
        XCTAssertTrue(r.state.editing)
        r.state.pointerUp(r.core(0), time: 0.6)
        XCTAssertEqual(r.launched, [])
        XCTAssertFalse(r.state.pointerBusy)
    }

    func testAHoldThenADragToThePageEdgeLiftsTheHeldTileAndEndsInOneOutcome() {
        let ids = (0..<40).map { "app\($0)" }
        let r = LiftRig(self, apps: ids)
        let from = r.core(0)
        XCTAssertTrue(r.state.pointerDown(from, time: 0))
        r.state.tick(at: 0.5)
        XCTAssertTrue(r.state.editing)
        let held = r.ids()[0]
        r.state.pointerMoved(CGPoint(x: from.x + 20, y: from.y), time: 0.6)
        XCTAssertEqual(r.state.lift?.entry.id, held)
        let edge = CGPoint(x: r.g.size.width - 5, y: from.y)
        r.state.pointerMoved(edge, time: 0.7)
        r.state.tick(at: 1.5)
        r.state.pointerUp(edge, time: 1.6)
        XCTAssertFalse(r.state.pointerBusy)
        XCTAssertNil(r.state.pressedID)
        XCTAssertTrue(r.state.editing, "the lift's end does not end the mode")
    }

    // MARK: The badges

    func testABadgePressDraggedOffAndLetGoDoesNothingToAnyTile() async {
        let r = await rig()
        let at = r.g.frame(of: r.g.cell(0)).offsetBy(dx: 0, dy: r.g.gridTop)
        let x = LaunchpadBadge.frames([.remove], cell: at.size, icon: r.g.icon, iconTop: r.g.iconTop)[0].frame
        let onBadge = CGPoint(x: at.minX + x.midX, y: at.minY + x.midY)
        XCTAssertFalse(r.state.pointerDown(onBadge, time: 0))
        r.state.pointerMoved(r.core(5), time: 0.1)
        r.state.pointerUp(r.core(5), time: 0.2)
        r.state.tick(at: 1)
        XCTAssertNil(r.state.lift)
        XCTAssertFalse(r.state.pointerBusy)
        XCTAssertEqual(r.launched, [])
        XCTAssertEqual(r.placed.count, 0)
        XCTAssertNil(r.state.removalAsk)
        XCTAssertTrue(r.state.editing)
    }

    func testAnAppThatLosesTheDoorsOfferLosesItsCrossAndAStalePressAsksNothing() async {
        let r = await rig()
        var offered: Set<String> = ["a", "b", "c", "d"]
        r.state.onVerdicts = { candidates in candidates.map { offered.contains($0.bundleID) ? .removable : .refused(.notOffered) } }
        offered.remove("a")
        r.catalog.reading = CatalogReading(apps: r.catalog.reading.apps.map {
            CatalogApp(id: $0.id, name: $0.name, path: $0.id == "a" ? "/Applications/Elsewhere/a.app" : $0.path)
        }, complete: true)
        r.state.update(snapshot: r.engine.read(reason: .refresh))
        await waitUntil("the cross goes") { !r.state.removable.contains("a") }
        XCTAssertTrue(r.state.badges(for: r.catalog.reading.apps[0]) == .hide)
        r.state.askToRemove("a")
        XCTAssertNil(r.state.removalAsk, "a stale press reaches nothing")
    }

    func testTheDoorGoingAwayInTheModeTakesEveryCrossAndNeverFillsThemBack() async {
        let r = await rig()
        r.state.onVerdicts = { _ in [] }
        r.catalog.reading = CatalogReading(apps: r.catalog.reading.apps.map { CatalogApp(id: $0.id, name: $0.name, path: "/x/\($0.id).app") }, complete: true)
        r.state.update(snapshot: r.engine.read(reason: .refresh))
        await waitUntil("the crosses go") { r.state.removable.isEmpty }
    }

    // MARK: The card

    func testACardForAnAppThatIsGoneDoesNotStayUpToConfirmNothing() async {
        let door = Gate()
        let r = await rig()
        r.state.onPreview = { await door.preview($0) }
        r.state.askToRemove("a")
        await waitUntil("asked") { door.asked == ["a"] }
        door.release(0, Gate.counted)
        await waitUntil("the card") { if case .asking? = r.state.removalAsk { true } else { false } }
        without(r, "a")
        await settle()
        XCTAssertNil(r.state.removalAsk, "the app the card is about is gone from the snapshot: a card that cannot remove anything is no card")
    }

    func testTwoCrossesPressedAtOnceAskOnceAndALateFirstAnswerRaisesNothingForTheSecond() async {
        let door = Gate()
        let r = await rig()
        r.state.onPreview = { await door.preview($0) }
        r.state.askToRemove("a")
        r.state.askToRemove("b")
        await settle()
        XCTAssertEqual(door.asked, ["a"], "one ask at a time")
        r.state.cancelRemoval()
        r.state.askToRemove("b")
        await waitUntil("b asked") { door.asked == ["a", "b"] }
        door.release(0, Gate.counted)
        await settle()
        if case .counting(let id, _)? = r.state.removalAsk { XCTAssertEqual(id, "b") } else { XCTFail("b is still being counted, the first answer is late: \(String(describing: r.state.removalAsk))") }
        door.release(1, Gate.counted)
        await waitUntil("b's card") { if case .asking("b", _, _)? = r.state.removalAsk { true } else { false } }
    }

    func testTheWindowClosingMidCountRaisesNoCardAndRemovesNothing() async {
        let door = Gate()
        let r = await rig()
        var removed = 0
        r.state.onPreview = { await door.preview($0) }
        r.state.onRemove = { _, _ in removed += 1 }
        r.state.askToRemove("a")
        await waitUntil("asked") { door.asked == ["a"] }
        r.state.shutdown()
        door.release(0, Gate.counted)
        await settle()
        XCTAssertNil(r.state.removalAsk)
        XCTAssertFalse(r.state.editing)
        r.pastTheDwell(); r.state.confirmRemoval()
        XCTAssertEqual(removed, 0)
    }

    func testAnAppRenamedOrMovedBetweenTheCrossAndTheButtonClosesTheCardAndRemovesNothing() async {
        let door = Gate()
        let r = await rig()
        var got: [AppRemovalCandidate] = []
        r.state.onPreview = { await door.preview($0) }
        r.state.onRemove = { candidate, _ in got.append(candidate) }
        r.state.askToRemove("a")
        await waitUntil("asked") { door.asked == ["a"] }
        door.release(0, Gate.counted)
        await waitUntil("the card") { if case .asking? = r.state.removalAsk { true } else { false } }
        r.catalog.reading = CatalogReading(apps: r.catalog.reading.apps.map {
            CatalogApp(id: $0.id, name: $0.id == "a" ? "Renamed" : $0.name, path: $0.id == "a" ? "/Applications/New/a.app" : $0.path)
        }, complete: true)
        r.state.update(snapshot: r.engine.read(reason: .refresh))
        XCTAssertNil(r.state.removalAsk, "the card counted another app than the one that is there now")
        r.pastTheDwell(); r.state.confirmRemoval()
        XCTAssertEqual(got, [])
    }

    func testTheButtonDoesNothingInTheFirstMomentsOfTheCard() async {
        let r = await rig()
        var got = 0
        r.state.onPreview = { _ in Gate.counted }
        r.state.onRemove = { _, _ in got += 1 }
        r.state.askToRemove("a")
        await waitUntil("the card") { if case .asking? = r.state.removalAsk { true } else { false } }
        r.state.confirmRemoval()
        XCTAssertEqual(got, 0, "a click aimed at the cross lands on the button")
        XCTAssertNotNil(r.state.removalAsk, "and the card stays")
        r.pastTheDwell(); r.state.confirmRemoval()
        XCTAssertEqual(got, 1)
    }

    // MARK: The Hidden card

    func testAHiddenAppIsNeverAskedAboutNorAskedToBeRemoved() async {
        let r = LiftRig(self, apps: ["a", "b", "h"])
        var asked: [[String]] = []
        r.state.onVerdicts = { asked.append($0.map(\.bundleID).sorted()); return $0.map { _ in .removable } }
        r.state.onPreview = { _ in Gate.counted }
        r.state.update(snapshot: r.engine.hide("h")!)
        r.state.beginEditing()
        await waitUntil("the verdicts") { r.state.removable == ["a", "b"] }
        XCTAssertEqual(asked, [["a", "b"]], "the hidden app's id is not put to the door")
        r.state.askToRemove("h")
        XCTAssertNil(r.state.removalAsk, "no card for a hidden app")
        r.state.askToRemove("a")
        await waitUntil("the card") { if case .asking? = r.state.removalAsk { true } else { false } }
        r.state.update(snapshot: r.engine.hide("a")!)
        XCTAssertNil(r.state.removalAsk, "the app was hidden under the card")
    }

    func testACardUpWhenItsFolderLeavesIsGoneWithNoNameKept() async {
        let folder = UUID()
        let r = LiftRig(self, apps: ["a", "b", "c"], layout: LaunchpadLayout(items: [.folder(.init(id: folder, name: "F", apps: ["b", "c"])), .app("a")]))
        r.state.onVerdicts = { candidates in candidates.map { _ in .removable } }
        r.state.onPreview = { _ in Gate.counted }
        r.state.beginEditing()
        r.state.open(folder: folder)
        await waitUntil("the verdicts") { r.state.removable == ["a", "b", "c"] }
        r.state.askToRemove("b")
        await waitUntil("the card") { if case .asking? = r.state.removalAsk { true } else { false } }
        r.state.setView(.categories)
        XCTAssertNil(r.state.removalAsk)
        XCTAssertNil(r.state.openFolder)
    }

    func testEscOverACardOverAnOpenFolderClosesTheCardFirstThenTheFolderThenTheMode() async {
        let folder = UUID()
        let r = LiftRig(self, apps: ["a", "b", "c"], layout: LaunchpadLayout(items: [.folder(.init(id: folder, name: "F", apps: ["b", "c"])), .app("a")]))
        r.state.onVerdicts = { candidates in candidates.map { _ in .removable } }
        r.state.onPreview = { _ in Gate.counted }
        r.state.beginEditing()
        r.state.open(folder: folder)
        await waitUntil("the verdicts") { r.state.removable == ["a", "b", "c"] }
        r.state.askToRemove("b")
        await waitUntil("the card") { if case .asking? = r.state.removalAsk { true } else { false } }
        r.state.escape()
        XCTAssertNil(r.state.removalAsk)
        XCTAssertEqual(r.state.openFolder, folder)
        r.state.escape()
        XCTAssertNil(r.state.openFolder)
        XCTAssertTrue(r.state.editing)
        r.state.escape()
        XCTAssertFalse(r.state.editing)
        XCTAssertEqual(r.closes, 0)
    }

    func testAKeyOrAClickOnTheTilesWhileTheCardIsUpActsOnNothing() async {
        let r = await rig()
        r.state.onPreview = { _ in Gate.counted }
        r.state.askToRemove("a")
        await waitUntil("the card") { if case .asking? = r.state.removalAsk { true } else { false } }
        XCTAssertFalse(r.state.pointerDown(r.core(1), time: 0), "the card is modal")
        r.state.activate()
        r.state.openApp("b", "B")
        r.state.backgroundClicked()
        XCTAssertEqual(r.launched, [])
        XCTAssertFalse(r.state.editing, "the control for the background click: it is the mode's exit, and the card goes with it")
        XCTAssertNil(r.state.removalAsk)
    }

    // MARK: The notices

    func testEveryOutcomesNoticeSaysItsSentenceOnceAndNamesTheAppOnce() {
        let name = "Zork"
        let notices: [LaunchNotice] = [
            .removed(size: "1 MB"), .removedWithLeftovers(size: "1 MB", left: "2 items"), .removeFailed(name: name, reason: "it is locked"),
            .removeStillRunning(name), .removeRefused(name), .removalBusy,
        ]
        var seen = Set<String>()
        for notice in notices {
            let text = LpStr.text(of: notice)
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("%"), "a placeholder left in: \(text)")
            XCTAssertTrue(seen.insert(text).inserted, "two outcomes say the same: \(text)")
            XCTAssertLessThanOrEqual(text.components(separatedBy: name).count - 1, 1, text)
            let named: Bool
            switch notice { case .removeFailed, .removeStillRunning, .removeRefused: named = true; default: named = false }
            if named { XCTAssertEqual(text.components(separatedBy: name).count - 1, 1, "the app is named once: \(text)") }
        }
    }

    func testARefusalThatArrivesAfterTheLastWindowLeftLeavesNoNoticeBehind() async {
        let rig = LaunchpadRig(self, label: "removal-late-refusal")
        let candidate = AppRemovalCandidate(bundleID: "a", path: "/Applications/a.app", name: "A")
        // The door is gone (the Uninstaller was turned off between the preview and the button); no window watches.
        await rig.model.removeApp(candidate, quittingIfRunning: false)
        XCTAssertNil(rig.model.notice, "no watcher is left to read it: it is dropped as `removeApp` says it is")
        let counted = await rig.model.previewRemoval(candidate)
        XCTAssertNil(counted)
        XCTAssertNil(rig.model.notice, "a refused preview that comes with no window left says nothing either")
    }

    func testALockDropsARemovalNoticeThatNamesAnApp() async {
        let rig = LaunchpadRig(self, label: "removal-notice-drop")
        let shown = Task { await rig.model.whileShown() }
        defer { shown.cancel() }
        for _ in 0..<500 where rig.model.snapshot == nil { try? await Task.sleep(for: .milliseconds(10)) }
        await rig.model.removeApp(AppRemovalCandidate(bundleID: "a", path: "/Applications/a.app", name: "A"), quittingIfRunning: false)
        XCTAssertEqual(rig.model.notice, .removeRefused("A"), "the control: no door, a watcher, a notice naming the app")
        rig.model.dropNamedNotice()
        XCTAssertNil(rig.model.notice)
    }

    func testARemovalThatLandsAfterTheWindowClosedRefreshesNothingAndLeavesNoNotice() async {
        let rig = LaunchpadRig(self, label: "removal-lands-late")
        let door = FakeAppRemoval()
        rig.model.removal = { door }
        await rig.model.removeApp(AppRemovalCandidate(bundleID: "a", path: "/Applications/a.app", name: "A"), quittingIfRunning: true)
        XCTAssertEqual(door.removed.count, 1)
        XCTAssertEqual(door.removed.first?.quitting, true)
        XCTAssertNil(rig.model.notice)
        XCTAssertNil(rig.model.snapshot, "nothing was read for a window that is not there")
        XCTAssertFalse(rig.catalog.reads.contains(.removal))
    }
}

extension LiftRig {
    /// The state's clock a second on, for a button that waits out its dwell.
    func pastTheDwell() { let now = state.clock(); state.clock = { now + 1 } }
}
