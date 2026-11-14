import XCTest
import CoreGraphics
import HelmRuntime
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// `KeepAwakeViewModel.apply` copies the payload's two condition sets as they
/// are; a model that dropped either would draw every rule as «Not applying».
/// One inert stand-in for every port: the engine under test only has to hold
/// the Mac for an app rule, which needs a running app and nothing else.
final class Inert: SleepAssertions, DisplayInfoPort, PowerInfoPort, LidInfoPort,
                            DisplayObserverPort, AppRunningPort, PointerPort, ClamshellPort,
                            Clock, @unchecked Sendable {
    var running: Set<String> = []
    var flatBattery = false
    var refusesSleepAssertion = false
    func preventSleep(display: Bool) -> Bool { !refusesSleepAssertion }
    func release() {}
    func builtInFlags() -> [Bool] { [] }
    func snapshot() -> (onBattery: Bool, percent: Int)? {
        flatBattery ? (onBattery: true, percent: 5) : (onBattery: false, percent: 100)
    }
    func supply() -> PowerSource.Supply? { flatBattery ? .battery : .mains }
    func hasLid() -> Bool { false }
    func hasBattery() -> Bool { flatBattery }
    func startObserving(_ onChange: @escaping @Sendable () -> Void) {}
    func stopObserving() {}
    func runningBundleIDs() -> Set<String> { running }
    func location() -> CGPoint? { nil }
    func move(to: CGPoint) {}
    func displayBounds(containing: CGPoint) -> CGRect? { nil }
    func isSudoersInstalled() -> Bool { false }
    func canDisableSleepWithoutPassword() -> Bool { false }
    func installSudoers(_ done: @escaping @Sendable (Bool) -> Void) { done(false) }
    func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void) { done(true) }
    func removeSudoersWithoutPassword() -> Bool { true }
    func setDisableSleep(_ on: Bool) -> Bool { true }
    func pmsetReport() -> String? { "" }
    func schedule(after: TimeInterval, _ block: @escaping @Sendable () -> Void) -> AnyObject { NSObject() }
    func now() -> Date { Date() }
}

@MainActor
final class TheModelDrawsWhatTheEnginePublishedTests: XCTestCase {

    func testARuleThatHoldsReachesTheModel() async {
        let store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        let settings = KeepAwakeSettings(store: store)
        settings.setAppTriggers([AppTrigger(bundleID: "com.example.render")])
        let ports = Inert()
        ports.running = ["com.example.render"]
        let engine = KeepAwakeEngine(settings: settings, store: store, assertions: ports,
                                     displayInfo: ports, displayObserver: ports,
                                     power: ports, apps: ports, pointer: ports,
                                     clamshell: ports, clock: ports, lidInfo: ports)
        engine.activate()
        let model = KeepAwakeViewModel(engine: engine)
        defer { model.stop() }

        await waitUntil("the model drew the rule", within: .seconds(5)) {
            model.triggeredConditions == [.app]
        }
        XCTAssertEqual(model.activeConditions, [.app])
        XCTAssertTrue(model.ruleHolds)
    }

    private func modelHoldingAnAppRule(_ ports: Inert) -> (KeepAwakeEngine, KeepAwakeViewModel) {
        let store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        let settings = KeepAwakeSettings(store: store)
        settings.setAppTriggers([AppTrigger(bundleID: "com.example.render")])
        ports.running = ["com.example.render"]
        let engine = KeepAwakeEngine(settings: settings, store: store, assertions: ports,
                                     displayInfo: ports, displayObserver: ports,
                                     power: ports, apps: ports, pointer: ports,
                                     clamshell: ports, clock: ports, lidInfo: ports)
        engine.activate()
        return (engine, KeepAwakeViewModel(engine: engine))
    }

    /// `notice` hands the model's two published facts to `KeepAwakeNotice.of`;
    /// a model that passed either one wrong would draw the wrong sentence.
    func testTheModelsNoticeIsTheBatteryGuardWhenTheGuardStoppedEverything() async {
        let ports = Inert()
        ports.flatBattery = true
        let (_, model) = modelHoldingAnAppRule(ports)
        defer { model.stop() }
        await waitUntil("the model drew the guard", within: .seconds(5)) { model.batteryStopped }
        XCTAssertEqual(model.notice, .battery)
    }

    func testTheModelsNoticeIsPausedWhenARuleWasStoppedByHand() async {
        let ports = Inert()
        let (engine, model) = modelHoldingAnAppRule(ports)
        defer { model.stop() }
        await waitUntil("the rule held", within: .seconds(5)) { model.ruleHolds }
        XCTAssertEqual(model.notice, .none)
        engine.stopSession()
        await waitUntil("the model drew the pause", within: .seconds(5)) { model.suppressed }
        XCTAssertEqual(model.notice, .paused)
    }

    func testTheModelsNoticeIsTheRefusalWhenMacOSRefusedTheAssertion() async {
        let ports = Inert()
        ports.refusesSleepAssertion = true
        let (_, model) = modelHoldingAnAppRule(ports)
        defer { model.stop() }
        await waitUntil("the model drew the refusal", within: .seconds(5)) { model.assertionRefused }
        XCTAssertEqual(model.notice, .assertionRefused)
    }
}

/// The slot under the buttons holds one sentence; when facts compete the
/// battery guard wins, then a refused sleep assertion, then a paused rule.
final class TheNoticeSlotHoldsOneSentenceTests: XCTestCase {
    func testTheBatteryGuardBeatsARefusalAndARefusalBeatsAPausedRule() {
        func notice(_ battery: Bool, _ refused: Bool, _ paused: Bool) -> KeepAwakeNotice {
            KeepAwakeNotice.of(batteryStopped: battery, assertionRefused: refused, suppressed: paused)
        }
        XCTAssertEqual(notice(true, true, true), .battery)
        XCTAssertEqual(notice(true, false, true), .battery)
        XCTAssertEqual(notice(true, true, false), .battery)
        XCTAssertEqual(notice(true, false, false), .battery)
        XCTAssertEqual(notice(false, true, true), .assertionRefused)
        XCTAssertEqual(notice(false, true, false), .assertionRefused)
        XCTAssertEqual(notice(false, false, true), .paused)
        XCTAssertEqual(notice(false, false, false), .none)
    }
}
