import XCTest
@testable import HelmApp

/// `bootstrap()` twice must not leave the first set of engines running.
///
/// `setEnabled` asks `if live[key] == nil` before building; `bootstrap` did
/// not, so a second call built a second engine for every enabled module and
/// assigned it over the first — without `deactivate()`. The first engine was
/// then freed with everything it had started still registered: for Layout that
/// is a live `CGEvent` tap on the main run loop holding a non-owning pointer to
/// the freed object, which is the SIGSEGV seen in this target roughly once in
/// six runs.
///
/// The assertion is **object identity**, not a count. A count is satisfied by
/// the dictionary having one entry per module, which it does either way — the
/// orphan is not in the dictionary, that is the whole problem. Identity says
/// the thing that is live now is the thing that was live before, which nothing
/// about scheduling can arrange.
@MainActor
final class BootstrapDoesNotOrphanEnginesTests: XCTestCase {

    /// `bootstrap()` above ran against the shared host, so the engines it built
    /// are real and would otherwise run for the rest of the process — for
    /// Layout, a live keyboard tap spell-checking everything typed while the
    /// suite runs. `ShutdownLetsTheEnginesGoTests` is what proves this call
    /// actually lets them go.
    override func tearDown() {
        ModuleHost.shared.shutdown()
        super.tearDown()
    }

    func testASecondBootstrapKeepsTheEnginesTheFirstOneBuilt() {
        let host = ModuleHost.shared
        host.bootstrap()
        let first = host.live.mapValues { ObjectIdentifier($0.engine) }
        XCTAssertFalse(first.isEmpty,
                       "no module was enabled, so this test would pass with the defect present")

        host.bootstrap()
        let second = host.live.mapValues { ObjectIdentifier($0.engine) }

        let replaced = first.filter { second[$0.key] != $0.value }.keys.sorted()
        XCTAssertTrue(replaced.isEmpty,
                      "a second bootstrap replaced the engine for \(replaced.joined(separator: ", ")) "
                      + "and never deactivated the first — each orphan keeps whatever it registered")
    }
}
