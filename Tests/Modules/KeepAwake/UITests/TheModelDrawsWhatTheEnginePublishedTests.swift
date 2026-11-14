import XCTest
import CoreGraphics
import HelmRuntime
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// `KeepAwakeViewModel.apply` copies the payload's two condition sets as they
/// are; a model that dropped either would draw every rule as «Not applying».
/// One inert stand-in for every port: the engine under test only has to hold
/// the Mac for an app rule, which needs a running app and nothing else.
private final class Inert: SleepAssertions, DisplayInfoPort, PowerInfoPort, LidInfoPort,
                            DisplayObserverPort, AppRunningPort, PointerPort, ClamshellPort,
                            Clock, @unchecked Sendable {
    var running: Set<String> = []
    func preventSleep(display: Bool) -> Bool { true }
    func release() {}
    func builtInFlags() -> [Bool] { [] }
    func snapshot() -> (onBattery: Bool, percent: Int)? { (onBattery: false, percent: 100) }
    func supply() -> PowerSource.Supply? { .mains }
    func hasLid() -> Bool { false }
    func hasBattery() -> Bool { false }
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
}
