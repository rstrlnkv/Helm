import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The inputs pass 16 did not feed the Hidden card: an app hidden or shown while it is open, a press by pointer or by arrows, a view
/// switched or a search typed while the prompt is up, a late answer after the window stopped showing, two gates at once, an answer
/// that comes twice. Each case first proves the thing it acts on is there.
@MainActor final class AHiddenCardUntriedInputsTests: XCTestCase {
    private func rig(_ mode: FakeAuthPort.Mode, apps: [String] = ["a", "b", "h"]) -> (LiftRig, LaunchpadScreenState, LaunchpadHiddenGate, FakeAuthPort, LaunchpadSnapshot) {
        let lift = LiftRig(self, apps: apps)
        let fake = FakeAuthPort(mode)
        let gate = LaunchpadHiddenGate(port: fake)
        let state = LaunchpadScreenState(geometry: lift.g, view: .categories, hidden: gate)
        state.setShown(true)
        let hidden = lift.engine.hide("h")!
        state.update(snapshot: hidden)
        return (lift, state, gate, fake, hidden)
    }

    func testAnAppHiddenWhileTheCardIsOpenAppearsInIt() async {
        let (lift, state, gate, _, _) = rig(.immediate(.success))
        state.open(folder: LaunchpadHiddenBlock.id)
        await gate.settled()
        XCTAssertEqual(state.folderApps.map(\.id), ["h"], "the control: the card is open with the one hidden app")
        state.update(snapshot: lift.engine.hide("a")!)
        XCTAssertEqual(state.openFolder, LaunchpadHiddenBlock.id)
        XCTAssertEqual(Set(state.folderApps.map(\.id)), ["h", "a"])
        XCTAssertEqual(gate.phase, .unlocked)
    }

    func testTheLastHiddenAppShownLeavesTheCardOpenAndEmpty() async {
        let (lift, state, gate, _, _) = rig(.immediate(.success))
        state.open(folder: LaunchpadHiddenBlock.id)
        await gate.settled()
        XCTAssertEqual(state.folderApps.map(\.id), ["h"], "the control: the card holds it")
        state.update(snapshot: lift.engine.unhide("h")!)
        XCTAssertEqual(state.openFolder, LaunchpadHiddenBlock.id, "the card stays, to say there is nothing")
        XCTAssertTrue(state.folderApps.isEmpty)
        XCTAssertEqual(gate.phase, .unlocked)
        state.escape()
        XCTAssertEqual(gate.phase, .locked)
    }

    func testThePointerOnTheEmptyBlockAsksOnceAndLaunchesNothing() async {
        let (_, state, gate, fake, _) = rig(.immediate(.success))
        let ids = state.pages[0].map(\.id)
        let slot = ids.firstIndex(of: LaunchpadHiddenBlock.id.uuidString)!
        XCTAssertEqual(ids.count, slot + 1, "the control: the Hidden block is the last tile")
        var launched: [String] = []
        state.onLaunch = { id, _ in launched.append(id) }
        let g = state.geometry
        let block = g.frame(of: state.slots[0][slot]).offsetBy(dx: 0, dy: g.gridTop)
        for quadrant in 0..<4 {
            let f = LaunchpadCategoryMark.frame(ofQuadrant: quadrant, size: g.largeMark, edge: g.largeEdge)
            let p = CGPoint(x: block.midX - g.largeMark / 2 + f.midX, y: block.minY + g.iconTop + f.midY)
            XCTAssertTrue(state.pointerDown(p, time: Double(quadrant)))
            XCTAssertNil(state.pressedIcon, "no icon is under the press of a block with no apps")
            state.pointerUp(p, time: Double(quadrant) + 0.05)
            await gate.settled()
            XCTAssertEqual(state.openFolder, LaunchpadHiddenBlock.id)
            state.escape()
            XCTAssertEqual(fake.evaluations, quadrant + 1)
        }
        XCTAssertTrue(launched.isEmpty)
    }

    func testTheArrowsThenReturnAskAndOpen() async {
        let (_, state, gate, fake, _) = rig(.immediate(.success))
        let ids = state.pages[0].map(\.id)
        for _ in 0..<ids.count where state.selection != ids.count - 1 { state.move(dx: 1, dy: 0) }
        XCTAssertEqual(state.selection, ids.count - 1, "the control: the choice is on the last tile")
        state.activate()
        await gate.settled()
        XCTAssertEqual(fake.evaluations, 1)
        XCTAssertEqual(state.openFolder, LaunchpadHiddenBlock.id)
        XCTAssertEqual(state.folderApps.map(\.id), ["h"])
    }

    func testTheViewSwitchedOrASearchTypedWhileThePromptIsUpOpensNothingWhenItAnswers() async {
        for how in ["the other view", "a typed search"] {
            let (_, state, gate, fake, _) = rig(.slow)
            state.open(folder: LaunchpadHiddenBlock.id)
            await fake.waitForAsks()
            XCTAssertEqual(gate.phase, .asking, "the control: the prompt is up (\(how))")
            if how == "the other view" { state.setView(.apps) } else { state.search = "a" }
            fake.release(.success)
            await gate.settled()
            XCTAssertEqual(gate.phase, .locked, how)
            XCTAssertNil(state.openFolder, how)
            XCTAssertTrue(state.folderApps.isEmpty, how)
        }
    }

    func testAnAnswerAfterTheWindowStoppedShowingOpensNothing() async {
        let (_, state, gate, fake, _) = rig(.slow)
        state.open(folder: LaunchpadHiddenBlock.id)
        await fake.waitForAsks()
        state.setShown(false)
        fake.release(.success)
        await gate.settled()
        XCTAssertEqual(gate.phase, .locked)
        XCTAssertNil(state.openFolder)
    }

    func testAnAnswerBeforeAnySnapshotOpensNothing() async {
        let fake = FakeAuthPort(.immediate(.success))
        let gate = LaunchpadHiddenGate(port: fake)
        let state = LaunchpadScreenState(geometry: .make(for: CGSize(width: 1280, height: 800), topSafe: 0), view: .categories, hidden: gate)
        state.setShown(true)
        state.open(folder: LaunchpadHiddenBlock.id)
        await gate.settled()
        XCTAssertEqual(fake.evaluations, 1, "the control: the prompt was asked")
        XCTAssertEqual(gate.phase, .locked)
        XCTAssertNil(state.openFolder)
    }

    func testTwoGatesLockApartAndTheirPortsAreTheirOwn() async {
        let (_, state, windowGate, windowFake, _) = rig(.immediate(.success))
        let pageFake = FakeAuthPort(.immediate(.success))
        let pageGate = LaunchpadHiddenGate(port: pageFake)
        state.open(folder: LaunchpadHiddenBlock.id)
        await windowGate.settled()
        pageGate.ask(reason: "x") {}
        await pageGate.settled()
        XCTAssertEqual([windowGate.phase, pageGate.phase], [.unlocked, .unlocked], "the control: both are open")
        pageGate.lock()
        XCTAssertEqual(windowGate.phase, .unlocked, "the page's lock shut the window's")
        XCTAssertEqual(state.openFolder, LaunchpadHiddenBlock.id)
        pageGate.ask(reason: "x") {}
        await pageGate.settled()
        state.shutdown()
        XCTAssertEqual(windowGate.phase, .locked)
        XCTAssertEqual(pageGate.phase, .unlocked, "the window's close shut the page's")
        XCTAssertEqual([windowFake.evaluations, pageFake.evaluations], [1, 2])
        pageGate.lock()
    }

    func testTwoAsksAnsweredTogetherUnlockOnceAndRunTheirCompletionOnce() async {
        let fake = FakeAuthPort(.slow)
        let gate = LaunchpadHiddenGate(port: fake)
        var completions: [Int] = []
        gate.ask(reason: "x") { completions.append(1) }
        await fake.waitForAsks(1)
        gate.lock()
        gate.ask(reason: "x") { completions.append(2) }
        await fake.waitForAsks(2)
        XCTAssertEqual(fake.evaluations, 2, "the control: two asks went to the port")
        fake.release(.success)
        await gate.settled()
        await grace()
        XCTAssertEqual(completions, [2], "only the newest ask is answered")
        XCTAssertEqual(gate.phase, .unlocked)
        gate.ask(reason: "x") { completions.append(3) }
        XCTAssertEqual(fake.evaluations, 2, "an unlocked gate asks nobody")
        XCTAssertEqual(completions, [2])
        gate.lock()
    }
}
