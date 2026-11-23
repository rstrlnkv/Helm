import HelmRuntime
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Stands for the Uninstaller's door (`AppRemovalService`): says what the test says, and records every call to `remove`, the one that moves anything.
@MainActor final class FakeAppRemoval: AppRemovalService {
    var ask: AppRemovalAsk = .ready(AppRemovalPreview(appBytes: 1000, leftoverCount: 2, leftoverBytes: 50, running: false))
    var report = AppRemovalReport(.moved, freedBytes: 1050)
    private(set) var removed: [(candidate: AppRemovalCandidate, quitting: Bool)] = []

    func verdicts(for candidates: [AppRemovalCandidate]) async -> [AppRemovalVerdict] { candidates.map { _ in .removable } }
    func preview(_ candidate: AppRemovalCandidate) async -> AppRemovalAsk { ask }
    func remove(_ candidate: AppRemovalCandidate, quittingIfRunning: Bool) async -> AppRemovalReport {
        removed.append((candidate, quittingIfRunning))
        return report
    }
}

/// The × only asks. Nothing is removed until the card's own button is pressed, and every other way out of the card, the mode or the window removes nothing;
/// the removal that is asked for goes to the door as the snapshot holds the app now, with the consent to quit only if the card said the app was open.
@MainActor final class TheRemoveBadgeAsksFirstAndCancelRemovesNothingTests: XCTestCase {
    private func rig(_ door: FakeAppRemoval) async -> LiftRig {
        let r = LiftRig(self, apps: ["a", "b"])
        r.state.onVerdicts = { await door.verdicts(for: $0) }
        r.state.onPreview = { candidate in if case .ready(let counted) = await door.preview(candidate) { counted } else { nil } }
        r.state.onRemove = { candidate, quitting in Task { @MainActor in _ = await door.remove(candidate, quittingIfRunning: quitting) } }
        r.state.beginEditing()
        await waitUntil("the verdicts") { r.state.removable == ["a", "b"] }
        return r
    }

    private func card(_ r: LiftRig) async {
        r.state.askToRemove("a")
        await waitUntil("the card") { if case .asking? = r.state.removalAsk { true } else { false } }
    }

    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    func testEveryWayOutOfTheCardRemovesNothing() async {
        let ways: [(String, (LiftRig) -> Void)] = [
            ("the Cancel button, the scrim", { $0.state.cancelRemoval() }),
            ("Esc", { $0.state.escape() }),
            ("typing in the search", { $0.state.search = "a" }),
            ("leaving the mode", { $0.state.endEditing() }),
            ("the category view", { $0.state.setView(.categories) }),
            ("closing the window", { $0.state.shutdown() }),
        ]
        for (way, act) in ways {
            let door = FakeAppRemoval()
            let r = await rig(door)
            await card(r)
            act(r)
            await settle()
            XCTAssertNil(r.state.removalAsk, way)
            XCTAssertEqual(door.removed.count, 0, way)
            if r.state.editing { r.state.askToRemove("a"); XCTAssertNotNil(r.state.removalAsk, "\(way): the control, the × still asks") }
        }
    }

    func testEscClosesTheCardBeforeTheModeAndTheWindow() async {
        let r = await rig(FakeAppRemoval())
        await card(r)
        r.state.escape()
        XCTAssertNil(r.state.removalAsk)
        XCTAssertTrue(r.state.editing)
        XCTAssertEqual(r.closes, 0)
    }

    func testAnAskThatIsStillCountingIsCancelledAndItsAnswerDropped() async {
        let door = FakeAppRemoval()
        let r = await rig(door)
        r.state.askToRemove("a")
        if case .counting? = r.state.removalAsk {} else { XCTFail("counting first") }
        r.state.cancelRemoval()
        await settle()
        XCTAssertNil(r.state.removalAsk, "the late answer does not raise the card")
    }

    func testConfirmRemovesOnceTheAppTheCardCounted() async {
        let door = FakeAppRemoval()
        let r = await rig(door)
        await card(r)
        r.state.update(snapshot: r.engine.read(reason: .refresh))
        XCTAssertNotNil(r.state.removalAsk, "a snapshot that holds the app as it was counted keeps the card")
        r.pastTheDwell(); r.state.confirmRemoval()
        await waitUntil("the removal") { door.removed.count == 1 }
        await settle()
        XCTAssertEqual(door.removed.count, 1)
        XCTAssertEqual(door.removed[0].candidate.path, "/Applications/a.app")
        XCTAssertEqual(door.removed[0].candidate.bundleID, "a")
        XCTAssertFalse(door.removed[0].quitting, "the card did not say the app was open")
        XCTAssertNil(r.state.removalAsk)
    }

    func testTheConsentToQuitIsTheCardsOwn() async {
        let door = FakeAppRemoval()
        door.ask = .ready(AppRemovalPreview(appBytes: nil, leftoverCount: 0, leftoverBytes: 0, running: true))
        let r = await rig(door)
        await card(r)
        r.pastTheDwell(); r.state.confirmRemoval()
        await waitUntil("the removal") { door.removed.count == 1 }
        XCTAssertTrue(door.removed[0].quitting)
    }

    func testAnAppTheDoorDoesNotOfferHasNoCard() async {
        let door = FakeAppRemoval()
        let r = await rig(door)
        r.state.askToRemove("zzz")
        XCTAssertNil(r.state.removalAsk, "not in the snapshot")
        r.state.endEditing()
        r.state.askToRemove("a")
        XCTAssertNil(r.state.removalAsk, "not in the mode")
        r.pastTheDwell(); r.state.confirmRemoval()
        await settle()
        XCTAssertEqual(door.removed.count, 0, "a confirm with no card asks nothing")
    }

    func testAPreviewTheDoorRefusesRaisesNoCardAndSaysSo() async {
        let door = FakeAppRemoval()
        door.ask = .refused(.notOffered)
        let rig = LaunchpadRig(self, label: "removal-refused")
        rig.model.removal = { door }
        let shown = Task { await rig.model.whileShown() }
        defer { shown.cancel() }
        for _ in 0..<500 where rig.model.snapshot == nil { try? await Task.sleep(for: .milliseconds(10)) }
        let counted = await rig.model.previewRemoval(AppRemovalCandidate(bundleID: "a", path: "/Applications/a.app", name: "A"))
        XCTAssertNil(counted)
        XCTAssertEqual(rig.model.notice, .removeRefused("A"))
        XCTAssertEqual(door.removed.count, 0)
    }

    func testARemovalHandedToTheDoorLandsWithNoWindowAndItsNoticeIsDropped() async {
        let door = FakeAppRemoval()
        let rig = LaunchpadRig(self, label: "removal-lands")
        rig.model.removal = { door }
        await rig.model.removeApp(AppRemovalCandidate(bundleID: "a", path: "/Applications/a.app", name: "A"), quittingIfRunning: false)
        XCTAssertEqual(door.removed.count, 1, "it reached the door")
        XCTAssertNil(rig.model.notice, "no watcher is left to read it")
    }
}
