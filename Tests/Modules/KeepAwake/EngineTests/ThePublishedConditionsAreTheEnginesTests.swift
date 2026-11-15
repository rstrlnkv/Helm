import XCTest
@testable import Module_KeepAwake_Engine

/// The sets `StatePayload` carries are the engine's own, and the 30-second
/// battery watch is a timer, not an observer.
///
/// `conditions` and `triggeredConditions` were retyped from `[String]` to
/// `Set<ActiveCondition>`; nothing asserted what reaches the stream, so an
/// emitter that published empty sets stayed green. The watch is the only thing
/// that ends an unattended session when the power observer stays silent.
final class ThePublishedConditionsAreTheEnginesTests: KeepAwakeEngineRig {

    private let render = "com.example.render"

    func testTheEmittedPayloadCarriesTheRuleThatHolds() async {
        settings.setAppTriggers([AppTrigger(bundleID: render)])
        apps.ids = [render]
        engine.activate()
        XCTAssertTrue(engine.isActive, "precondition: the app rule holds the Mac")

        var first: KeepAwakeEngine.StatePayload?
        for await p in engine.stream() { first = p; break }

        XCTAssertEqual(first?.conditions, [.app])
        XCTAssertEqual(first?.triggeredConditions, [.app])
        XCTAssertEqual(first?.holdingApps, [render])
    }

    func testTheBatteryWatchEndsASessionTheObserverNeverHeardAbout() {
        engine.activate()
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.isActive, "precondition")

        // The charge falls and the power observer says nothing.
        power.snap = (onBattery: true, percent: 5)
        clock.fire(after: 30)

        XCTAssertFalse(engine.isActive,
                       "the thirty-second watch did not look at the charge")
    }
}
