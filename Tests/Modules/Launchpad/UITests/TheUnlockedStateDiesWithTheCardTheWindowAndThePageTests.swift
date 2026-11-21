import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Every way the card goes (Esc, a click on the background, the other view, a typed search) and the window going lock the gate,
/// so the next press asks the system again; the page's gate locks by `lock()`. Nothing is written to the layout file.
@MainActor final class TheUnlockedStateDiesWithTheCardTheWindowAndThePageTests: XCTestCase {
    private func unlocked(_ rig: HiddenRig, asks: Int) async {
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        await rig.gate.settled()
        XCTAssertEqual(rig.gate.phase, .unlocked, "the control: unlocked")
        XCTAssertEqual(rig.state.openFolder, LaunchpadHiddenBlock.id)
        XCTAssertEqual(rig.fake.evaluations, asks)
    }

    func testEveryCloserLocksAndTheNextPressAsksAgain() async {
        let closers: [(String, (LaunchpadScreenState) -> Void)] = [
            ("Esc", { $0.escape() }),
            ("background", { $0.backgroundClicked() }),
            ("the other view", { $0.setView(.apps) }),
            ("a typed search", { $0.search = "a" }),
            ("the window", { $0.shutdown() }),
        ]
        let rig = HiddenRig(.immediate(.success))
        for (index, (name, close)) in closers.enumerated() {
            await unlocked(rig, asks: index + 1)
            close(rig.state)
            XCTAssertEqual(rig.gate.phase, .locked, name)
            XCTAssertNil(rig.state.openFolder, name)
            // The grid view of this hand-made snapshot still lists the app (no engine reconciled it): only the card is the question there.
            if name != "the other view" { XCTAssertFalse(rig.hiddenIsShown, name) }
            rig.state.search = ""
            rig.state.setView(.categories)
        }
        XCTAssertEqual(rig.fake.evaluations, closers.count)
    }

    func testTheUnlockedCardIsNotLeftUnlockedBehindAnotherCard() async {
        let rig = HiddenRig(.immediate(.success))
        await unlocked(rig, asks: 1)
        guard let other = rig.state.pages.joined().compactMap({ entry -> UUID? in
            if case .folder(let id, _, _, _) = entry, id != LaunchpadHiddenBlock.id { return id }
            return nil
        }).first else { return XCTFail("the control: a category block is shown") }
        rig.state.open(folder: other)
        XCTAssertEqual(rig.state.openFolder, other, "the control: another card replaced it")
        XCTAssertEqual(rig.gate.phase, .locked, "the Hidden block's lock stays open behind another card")
        XCTAssertFalse(rig.hiddenIsShown)
    }

    func testThePagesGateLocksByLock() async {
        let fake = FakeAuthPort(.immediate(.success))
        let gate = LaunchpadHiddenGate(port: fake)
        gate.ask(reason: "x") {}
        await gate.settled()
        XCTAssertEqual(gate.phase, .unlocked, "the control: unlocked")
        gate.lock()
        XCTAssertEqual(gate.phase, .locked)
        gate.ask(reason: "x") {}
        await fake.waitForAsks(2)
        XCTAssertEqual(fake.evaluations, 2)
        gate.lock()
    }

    func testNothingIsWrittenToTheLayoutFile() async throws {
        let rig = LiftRig(self, apps: ["a", "h"])
        let hidden = rig.engine.hide("h")
        XCTAssertNotNil(hidden, "the control: h is hidden")
        let before = try? Data(contentsOf: rig.layoutFile)
        XCTAssertNotNil(before, "the control: the file is there")
        let fake = FakeAuthPort(.immediate(.success))
        let gate = LaunchpadHiddenGate(port: fake)
        let state = LaunchpadScreenState(geometry: rig.g, view: .categories, hidden: gate)
        state.setShown(true)
        state.update(snapshot: hidden)
        state.open(folder: LaunchpadHiddenBlock.id)
        await gate.settled()
        XCTAssertEqual(state.folderApps.map(\.id), ["h"], "the control: unlocked, the card holds it")
        state.escape()
        XCTAssertEqual(try? Data(contentsOf: rig.layoutFile), before)
    }
}
