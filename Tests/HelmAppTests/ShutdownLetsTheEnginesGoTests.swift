import XCTest
import HelmContract
import HelmRuntime
@testable import HelmApp

/// `shutdown()` is what stands between "a test called `bootstrap()`" and "the
/// suite spends the rest of the process with a live keyboard tap in it".
///
/// `ModuleHost.shared` is a singleton, so a bootstrap in any test builds every
/// enabled module's *real* engine: Layout's `CGKeyTap` sits on the main run
/// loop with the accessibility grant and feeds every real keystroke into the
/// engine, which spell-checks words — visible as endless contactsd/CoreData
/// 4097 retry spam through the remainder of `swift test`. The teardowns in
/// `BootstrapDoesNotOrphanEnginesTests` and `DisclosureProbe` call `shutdown()`
/// to prevent that; this test is what makes those calls a guard rather than a
/// gesture.
///
/// The assertion is that the engines are **gone**, not that `live` is empty —
/// `live` emptied is `shutdown()` reading back its own write. An engine still
/// alive after the host let go of it is being held by something it should have
/// cancelled (`Task { [weak self] }` holds strongly once the body runs,
/// CLAUDE.md § Memory), and whatever it registered is still registered. Freed
/// is the state no leftover can survive: the tap's own `deinit` is unreachable
/// while the engine lives, and certain once it does not.
@MainActor
final class ShutdownLetsTheEnginesGoTests: XCTestCase {

    /// Belt and braces: if the assertion below ever fails, the suite should
    /// still not keep the engines that *did* deactivate.
    override func tearDown() {
        ModuleHost.shared.shutdown()
        super.tearDown()
    }

    private final class Grip {
        weak var engine: (any ModuleEngine)?
        init(_ engine: any ModuleEngine) { self.engine = engine }
    }

    func testShutdownFreesEveryEngineBootstrapBuilt() {
        let host = ModuleHost.shared
        host.bootstrap()
        // The subject has to have happened first, or "no engine survived"
        // is an absence a bootstrap that built nothing satisfies too.
        XCTAssertFalse(host.live.isEmpty,
                       "no module was enabled, so this test would prove nothing")
        let grips = host.live.map { (key: $0.key, grip: Grip($0.value.engine)) }

        // A phase a module left open goes with the module — `shutdown` sweeps
        // the way `disable` does. Pinned with an interval opened here, because
        // "no interval remains" is an absence a run that never opened one
        // satisfies too. Ended in the teardown as well, so a failure of this
        // test does not leave its own probe behind for the next one.
        let interval = host.live.keys.sorted()[0] + ".shutdown-probe"
        HelmActivity.begin(interval)
        addTeardownBlock { HelmActivity.end(interval) }
        XCTAssertTrue(HelmActivity.running.contains { $0.label == interval },
                      "the probe interval never opened, so the sweep check below is vacuous")

        host.shutdown()

        XCTAssertFalse(HelmActivity.running.contains { $0.label == interval },
                       "shutdown left the module's open interval behind — a leaked phase "
                       + "naming a module that is no longer there")

        XCTAssertTrue(host.live.isEmpty,
                      "shutdown left \(host.live.keys.sorted().joined(separator: ", ")) live")
        // An engine's own tasks release it when they see the cancellation
        // `deactivate()` sent, which takes a turn of the run loop, not zero.
        for _ in 0..<200 {
            if grips.allSatisfy({ $0.grip.engine == nil }) { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let survivors = grips.filter { $0.grip.engine != nil }.map(\.key).sorted()
        XCTAssertTrue(survivors.isEmpty,
                      "shutdown deactivated and dropped every engine, and "
                      + "\(survivors.joined(separator: ", ")) stayed alive anyway — "
                      + "something is holding what should have been cancelled, and "
                      + "whatever it registered is still registered")
    }
}
