import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A timed shot from the panel is taken from the screen as it is after the last second, and not before.** The freeze
/// the person picked on is the first; the shot of an area is a crop of a second freeze taken after the last tick
/// (painted green, red and blue in turn, so a file says which freeze it came from), a window is asked for by its id after it.
/// And the inputs the demo never makes: the timer switched while the overlay is up or while it counts, a display gone
/// or replaced during the wait, a window that closed.
@MainActor
final class TheTimedShotIsTakenAfterTheCountdownTests: XCTestCase {
    typealias Rig = PanelRig.Rig

    private final class Ticks: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var count: Int { lock.withLock { n } }
        func bump() -> Int { lock.withLock { n += 1; return n } }
    }

    private func pickedArea(_ box: Rig) async throws -> CaptureOverlay {
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        return overlay
    }

    func testTheSecondFreezeIsTakenAfterTheLastTickAndNotBeforeAndTheShotIsCutFromIt() async throws {
        let ticks = Ticks()
        let box = try PanelRig.rig(timer: .five, tick: { _ in _ = ticks.bump() })
        let atFreeze = FreezeLog()
        box.screen.onFreeze = { n in atFreeze.record(n, ticks.count) }
        _ = try await pickedArea(box)
        XCTAssertEqual(box.screen.freezes, 1)
        XCTAssertEqual(ticks.count, 0, "the countdown ran before the person took the area")
        box.controller.capture(from: .area)
        await waitUntil("the timed shot was written") { box.disk.written == 1 }
        XCTAssertEqual(box.screen.freezes, 2, "a timed area froze \(box.screen.freezes) times, not twice")
        XCTAssertEqual(atFreeze.ticks(at: 1), 0)
        XCTAssertEqual(atFreeze.ticks(at: 2), 5, "the second freeze was not after the fifth tick")
        XCTAssertEqual(PanelRig.colourAtCentre(of: box.disk.last), "red", "the file is not cut from the second freeze")
        XCTAssertEqual(PanelRig.size(of: box.disk.last), PanelRig.area.size, "the crop is not the rectangle that was picked")
    }

    func testAnUntimedShotFreezesOnceAndWaitsForNothing() async throws {
        let ticks = Ticks()
        let box = try PanelRig.rig(timer: .none, tick: { _ in _ = ticks.bump() })
        _ = try await pickedArea(box)
        box.controller.capture(from: .area)
        await waitUntil("the shot was written") { box.disk.written == 1 }
        XCTAssertEqual(box.screen.freezes, 1)
        XCTAssertEqual(ticks.count, 0)
        XCTAssertEqual(PanelRig.colourAtCentre(of: box.disk.last), "green", "an untimed shot is cut from the freeze the person saw")
    }

    func testATimedWindowIsTheLiveOneAskedForByIdAfterTheLastTick() async throws {
        let ticks = Ticks()
        let box = try PanelRig.rig(timer: .ten, tick: { _ in _ = ticks.bump() })
        let asked = FreezeLog()
        box.screen.windowAnswer = { id in
            asked.record(Int(id), ticks.count)
            return .image(PanelRig.solid(0, 0, 1, width: 300, height: 200))
        }
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        box.controller.capture(from: .window)
        await waitUntil("the shot was written") { box.disk.written == 1 }
        XCTAssertEqual(asked.ticks(at: 7), 10, "the window was asked for before the tenth tick")
        XCTAssertEqual(box.screen.windowAsks, 1)
        XCTAssertEqual(box.screen.freezes, 1, "a timed window froze the screen again")
        XCTAssertEqual(PanelRig.colourAtCentre(of: box.disk.last), "blue", "the live window's own picture was not the one saved")
    }

    /// The window closed during the countdown: what is saved is what it looked like at the pick, cut from the freeze.
    /// Written down so a change of that decision is a decision and not an accident.
    func testAWindowGoneDuringTheCountdownIsCutFromTheFreezeOfThePick() async throws {
        let box = try PanelRig.rig(timer: .five)
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        try XCTUnwrap(box.held.overlay).mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        box.controller.capture(from: .window)
        await waitUntil("something was written") { box.disk.written == 1 }
        XCTAssertEqual(box.screen.windowAsks, 1)
        XCTAssertEqual(box.screen.freezes, 1)
        await waitUntil("the machine was freed") { !box.controller.isBusy }
    }

    func testAWindowCaptureDeniedAfterTheCountdownWritesNothingAndFreesTheMachine() async throws {
        let box = try PanelRig.rig(timer: .five)
        box.screen.windowAnswer = { _ in .denied }
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        try XCTUnwrap(box.held.overlay).mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        box.controller.capture(from: .window)
        await waitUntil("the machine was freed") { !box.controller.isBusy }
        XCTAssertEqual(box.screen.windowAsks, 1)
        XCTAssertEqual(box.disk.written, 0)
    }

    // MARK: - The display the area was drawn on

    private func timedAreaWith(fromTheFirstFreeze: Bool = false,
                               _ shape: @escaping @Sendable (Int, [FrozenDisplay]) -> [FrozenDisplay]) async throws -> Rig {
        let box = try PanelRig.rig(timer: .five)
        let paint = box.screen.shape
        box.screen.shape = { n, frames in n == 1 && !fromTheFirstFreeze ? paint(n, frames) : shape(n, paint(n, frames)) }
        _ = try await pickedArea(box)
        box.controller.capture(from: .area)
        await waitUntil("the machine was freed") { !box.controller.isBusy }
        return box
    }

    func testTheDisplayGoneDuringTheCountdownIsARefusalAndNothingIsWritten() async throws {
        let gone = try PanelRig.rig().display
        let box = try await timedAreaWith { _, frames in frames.filter { $0.id != gone } }
        XCTAssertEqual(box.screen.freezes, 2)
        XCTAssertEqual(box.disk.written, 0, "a shot was written from a display that is gone")
        XCTAssertEqual(PanelRig.refusalBody(of: box.controller), ScStr.refusal(.displayGone), "a display that is gone went unsaid")
    }

    func testADisplayThatCameBackUnderAnotherUUIDIsNotTheOneThatWasPicked() async throws {
        let box = try await timedAreaWith { _, frames in
            frames.map { FrozenDisplay(id: $0.id, frame: $0.frame, scale: $0.scale, image: $0.image, uuid: "OTHER-" + ($0.uuid ?? "")) }
        }
        XCTAssertEqual(box.disk.written, 0, "the id was reused by another display and the shot was cut from it")
        XCTAssertEqual(PanelRig.refusalBody(of: box.controller), ScStr.refusal(.displayGone), "another display under the old id went unsaid")
    }

    func testTheSameDisplayUnderANewIdIsFoundByItsUUID() async throws {
        let box = try await timedAreaWith { _, frames in
            frames.map { FrozenDisplay(id: DisplayID($0.id.raw &+ 1000), frame: $0.frame, scale: $0.scale, image: $0.image, uuid: $0.uuid) }
        }
        XCTAssertEqual(box.disk.written, 1, "the display came back under a new id and the shot was lost")
        XCTAssertEqual(PanelRig.colourAtCentre(of: box.disk.last), "red")
    }

    func testADisplayWithNoUUIDIsFoundByItsId() async throws {
        let box = try await timedAreaWith(fromTheFirstFreeze: true) { _, frames in
            frames.map { FrozenDisplay(id: $0.id, frame: $0.frame, scale: $0.scale, image: $0.image, uuid: nil) }
        }
        XCTAssertEqual(box.disk.written, 1)
    }

    /// The display was swapped for a smaller one: the rectangle picked no longer fits. What is delivered is either the
    /// whole rectangle or nothing, never a smaller picture than the person drew.
    func testADisplayThatShrankDuringTheCountdownNeverDeliversASmallerPictureThanWasDrawn() async throws {
        let box = try await timedAreaWith { _, frames in
            frames.map { FrozenDisplay(id: $0.id, frame: CGRect(x: $0.frame.minX, y: $0.frame.minY, width: 300, height: 200), scale: $0.scale,
                                       image: PanelRig.paint(2, width: 300, height: 200), uuid: $0.uuid) }
        }
        XCTAssertTrue(PanelRig.hasToast(box.controller), "the reader of the toast looks at nothing")
        XCTAssertEqual(box.disk.written, 0,
                       "a 400 x 300 area was delivered as \(String(describing: PanelRig.size(of: box.disk.last))) with no word")
        XCTAssertEqual(PanelRig.refusalBody(of: box.controller), ScStr.refusal(.displayGone),
                       "nothing was written and nobody was told why: the rectangle no longer fits the display")
    }

    // MARK: - The timer meets the person

    func testTheTimerSwitchedOnWhileTheOverlayIsUpIsKept() async throws {
        let ticks = Ticks()
        let box = try PanelRig.rig(timer: .none, tick: { _ in _ = ticks.bump() })
        _ = try await pickedArea(box)
        box.controller.bar.model.toggleTimer()
        box.controller.capture(from: .area)
        await waitUntil("the shot was written") { box.disk.written == 1 }
        XCTAssertEqual(ticks.count, 5, "a timer switched on over the open overlay was not waited")
        XCTAssertEqual(box.screen.freezes, 2)
    }

    func testTheTimerSwitchedOffWhileTheOverlayIsUpIsKept() async throws {
        let ticks = Ticks()
        let box = try PanelRig.rig(timer: .ten, tick: { _ in _ = ticks.bump() })
        _ = try await pickedArea(box)
        box.controller.bar.model.choose(CaptureTimer.none)
        box.controller.capture(from: .area)
        await waitUntil("the shot was written") { box.disk.written == 1 }
        XCTAssertEqual(ticks.count, 0)
        XCTAssertEqual(box.screen.freezes, 1)
    }

    func testALengthChangedDuringTheCountdownDoesNotChangeTheCountdownInFlight() async throws {
        let ticks = Ticks()
        let storeRef = StoreBox()
        let box = try PanelRig.rig(timer: .five, tick: { _ in
            if ticks.bump() == 2 { await MainActor.run { storeRef.store?.set(30, for: ScreenshotsSettings.Key.timer) } }
        })
        storeRef.store = box.store
        _ = try await pickedArea(box)
        box.controller.capture(from: .area)
        await waitUntil("the shot was written") { box.disk.written == 1 }
        XCTAssertEqual(ticks.count, 5, "the countdown followed the store mid-way")
    }

    func testThirtyWithNoLengthKeyCountsThirtyAndTheRingKnowsIt() async throws {
        let ticks = Ticks()
        let box = try PanelRig.rig(timer: .thirty, tick: { _ in _ = ticks.bump() })
        XCTAssertNil(box.store.object(ScreenshotsSettings.Key.timerLength))
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.screen)
        box.controller.capture(from: .screen)
        await waitUntil("the shot was written") { box.disk.written == 1 }
        XCTAssertEqual(ticks.count, 30)
        XCTAssertEqual(box.controller.bar.model.countdownLength, 30)
    }
}

/// What a fake saw, by key: the tick count at the moment of each call.
private final class FreezeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Int: Int] = [:]
    func record(_ key: Int, _ ticks: Int) { lock.withLock { seen[key] = ticks } }
    func ticks(at key: Int) -> Int? { lock.withLock { seen[key] } }
}

private final class StoreBox: @unchecked Sendable { var store: NamespacedStore? }
