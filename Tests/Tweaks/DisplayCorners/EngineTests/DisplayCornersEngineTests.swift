import CoreGraphics
import HelmRuntime
import XCTest
@testable import Tweak_DisplayCorners_Engine

/// What the engine decides over fakes: what a step changes, what sleep ignores, which scale a radius is held
/// at, how fast the window list is asked, what the pointer fallback says, and when the pointer is put back.
@MainActor
final class DisplayCornersEngineTests: XCTestCase {

    func testAStepOfTheRadiusResizesTheWindowsInPlace() {
        let rig = Rig()
        rig.engine.activate()
        let before = rig.masks.standing
        XCTAssertEqual(before.count, 2, "the subject did not happen")
        let ticks = rig.ticker.starts, pointers = rig.pointer.starts
        rig.engine.stepRadius(direction: 1)
        let diff = rig.masks.shows.last
        XCTAssertEqual(diff?.changed.count, 2)
        XCTAssertEqual(diff?.added.count, 0)
        XCTAssertEqual(diff?.removed.count, 0)
        XCTAssertEqual(rig.masks.standing, before, "a window was replaced")
        XCTAssertEqual(rig.ticker.starts, ticks, "a step restarted the ticker")
        XCTAssertEqual(rig.pointer.starts, pointers, "a step restarted the pointer")
        XCTAssertEqual(rig.engine.state.radiusPixels, 28.5)
    }

    func testAScreenChangeWhileAsleepDoesNothingUntilTheDisplaysWake() {
        let rig = Rig()
        rig.engine.activate()
        rig.events.fire(.displaysSlept)
        XCTAssertEqual(rig.masks.removals, 1, "the subject did not happen: sleep left the masks up")
        XCTAssertFalse(rig.ticker.isRunning)
        let reads = rig.displays.reads, shows = rig.masks.shows.count
        rig.displays.list = [Rig.builtIn, Rig.external]
        rig.store.set(true, for: "external")
        rig.events.fire(.screensChanged)
        XCTAssertEqual(rig.displays.reads, reads)
        XCTAssertEqual(rig.masks.shows.count, shows)
        rig.events.fire(.displaysWoke)
        XCTAssertEqual(rig.masks.shows.count, shows + 1)
        XCTAssertTrue(rig.ticker.isRunning)
    }

    func testARadiusIsHeldAtTheBuiltInScaleRememberedWithTheLidClosed() {
        let backing = InMemoryKeyValueStore()
        let first = Rig(store: Rig.store(over: backing))
        first.engine.activate()
        XCTAssertEqual(first.store.object("builtInScale") as? Double, 2, "the subject did not happen: the scale was not remembered")
        first.engine.deactivate()

        let closed = Rig(store: Rig.store(over: backing), displays: [Rig.external])
        closed.store.set(true, for: "external")
        closed.engine.activate()
        XCTAssertFalse(closed.masks.shows.isEmpty)
        XCTAssertEqual(closed.engine.state.referenceScale, 2)
        XCTAssertEqual(closed.engine.state.radiusPixels, 28)
        closed.engine.setPreset(points: 20)
        XCTAssertEqual(closed.store.object("radiusPixels") as? Double, 40)
    }

    func testTheWindowListIsAskedSlowlyAtRestAndFastWhileAWindowMoves() {
        let rig = Rig()
        rig.engine.activate()
        XCTAssertEqual(rig.ticker.hz, 20, "the subject did not happen: no idle rate")
        rig.settle()
        rig.clock.time = 101
        rig.ticker.tick()
        XCTAssertEqual(rig.ticker.hz, 20)
        XCTAssertEqual(rig.ticker.starts, 1, "a tick at rest restarted the ticker")

        for number in rig.masks.standing.values { rig.windows.bounds[number] = CGRect(x: 900, y: 0, width: 28, height: 28) }
        rig.clock.time = 102
        rig.ticker.tick()
        XCTAssertEqual(rig.ticker.hz, 120)
        XCTAssertEqual(rig.masks.rounding.map(\.rounded), [false])
        XCTAssertEqual(rig.engine.state.rounded, [1: false])

        rig.settle()
        rig.clock.time = 103
        rig.ticker.tick()
        XCTAssertEqual(rig.ticker.hz, 20)
        XCTAssertEqual(rig.masks.rounding.map(\.rounded), [false, true])
        XCTAssertEqual(rig.engine.state.rounded, [1: true])
    }

    func testASpaceChangeSamplesAtOnceAndKeepsTheRateUpForAWhile() {
        let rig = Rig()
        rig.engine.activate()
        rig.settle()
        rig.events.fire(.spaceChanged)
        XCTAssertEqual(rig.windows.asked.count, 1, "the subject did not happen: no sample")
        XCTAssertEqual(rig.ticker.hz, 120)
        rig.clock.time += 2
        rig.ticker.tick()
        XCTAssertEqual(rig.ticker.hz, 20)
    }

    func testTheSystemTakingTheTapAwayIsSaidAsMonitorsOnly() {
        let rig = Rig()
        rig.engine.activate()
        XCTAssertEqual(rig.engine.state.pointer, .tap, "the subject did not happen")
        rig.pointer.drop()
        XCTAssertEqual(rig.engine.state.pointer, .monitorsOnly)
    }

    func testNeitherATapNorMonitorsIsSaidAsUnavailable() {
        let rig = Rig()
        rig.pointer.answers = .unavailable
        rig.engine.activate()
        XCTAssertEqual(rig.pointer.starts, 1, "the subject did not happen")
        XCTAssertEqual(rig.engine.state.pointer, .unavailable)
    }

    func testThePointerIsPutBackOnTheCurveAndLeftAloneAwayFromTheCorner() {
        let rig = Rig()
        rig.engine.activate()
        rig.settle()
        rig.clock.time = 101
        rig.ticker.tick()
        XCTAssertEqual(rig.engine.state.rounded, [1: true], "the subject did not happen: the display is not rounded and at rest")

        let reads = rig.pointer.locationReads
        rig.pointer.position = CGPoint(x: 500, y: 500)
        rig.pointer.move(to: CGPoint(x: 500, y: 500))
        XCTAssertEqual(rig.pointer.locationReads, reads, "a move away from every corner read the pointer")
        XCTAssertTrue(rig.pointer.warps.isEmpty)

        let corner = CGPoint(x: 0.5, y: 981.5)
        rig.pointer.position = corner
        rig.pointer.move(to: corner)
        XCTAssertEqual(rig.pointer.warps.count, 1)
        guard let target = rig.pointer.warps.first,
              let spec = rig.engine.state.masks.first(where: { $0.key.corner == .bottomLeft }) else { return XCTFail("no warp") }
        let local = CGPoint(x: target.x, y: 982 - target.y)
        XCTAssertTrue(CornerPath.visible(size: spec.frame.width, radius: spec.radius, corner: .bottomLeft).contains(local),
                      "the pointer was put at \(target), which is on the mask")
    }

    func testARefusedWarpLeavesNoContact() {
        let rig = Rig()
        rig.pointer.refusesWarp = true
        rig.engine.activate()
        rig.settle()
        rig.ticker.tick()
        let reads = rig.pointer.locationReads
        let corner = CGPoint(x: 0.5, y: 981.5)
        rig.pointer.position = corner
        rig.pointer.move(to: corner)
        rig.pointer.move(to: corner)
        XCTAssertEqual(rig.pointer.locationReads, reads + 2, "the subject did not happen: the pointer was not looked at twice")
        XCTAssertTrue(rig.pointer.warps.isEmpty)
    }
}
