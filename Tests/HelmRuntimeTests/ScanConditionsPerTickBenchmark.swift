import CoreGraphics
import XCTest
@testable import HelmRuntime

/// What one tick of `ScanCoordinator.considerAll` costs to *decide*, and what
/// the decision used to cost.
///
/// **The hoist this file measured has been applied.** `verdict(for:)` was
/// called once per scannable module and read the machine each time, so a tick
/// over three modules was 3 idle reads, 3 power reads and 6
/// `CGSessionCopyCurrentDictionary` calls — `ownsTheConsole` and
/// `screenIsLocked` each make their own — plus three `SecItemCopyMatching`
/// round trips, because `AppSettings.disabledScans` verifies its seal on every
/// read. None of those answers can differ inside one tick. The coordinator now
/// samples them once into `ScanCoordinator.Conditions` and hands the same
/// snapshot to every module.
///
/// So `testOneTickAcrossThreeModules` is the *before and after* rather than a
/// description of the code: `asIs` is the shape that shipped until the hoist,
/// `hoisted` is the shape that ships now. It asserts nothing and cannot — it
/// times system calls, and a number is not a threshold anybody can defend on
/// another Mac. What guards the hoist is the type: `verdict(for:in:)` takes a
/// snapshot and has no way to read the machine itself.
///
/// The primitives are measured here rather than through the coordinator because
/// this is `HelmRuntimeTests` and `verdict(for:in:)` is in `HelmApp`. (`HelmApp`
/// does have a test target — `HelmAppTests` — which this file used to deny.)
///
/// `HELM_BENCH=1 swift test --filter ScanConditionsPerTickBenchmark`
final class ScanConditionsPerTickBenchmark: XCTestCase {

    private func timeIt(_ label: String, iterations: Int = 1000, _ body: () -> Void) -> Double {
        _ = SystemIdle.seconds() // pay the documented 34.4 ms cold cost once, outside the timing
        let start = Date()
        for _ in 0..<iterations { body() }
        let elapsed = Date().timeIntervalSince(start)
        let perCall = elapsed / Double(iterations) * 1000
        print(String(format: "%@: %.5f ms/call (%d calls in %.4f s)",
                     label, perCall, iterations, elapsed))
        return perCall
    }

    func testEachPrimitiveWarm() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        _ = timeIt("SystemIdle.seconds()") { _ = SystemIdle.seconds() }
        _ = timeIt("PowerSource.isOnMains") { _ = PowerSource.isOnMains }
        _ = timeIt("CGSessionCopyCurrentDictionary") {
            _ = CGSessionCopyCurrentDictionary()
        }
    }

    /// One tick over three modules, the way it used to be driven against the
    /// way it is driven now. `asIs` is the retired shape — `verdict(for:)` per
    /// module, each reading idle, power and the session dictionary twice.
    func testOneTickAcrossThreeModules() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        _ = SystemIdle.seconds() // warm, as the app's first launch already paid this

        func onePerModuleVerdict() {
            _ = SystemIdle.seconds()
            _ = PowerSource.isOnMains
            _ = CGSessionCopyCurrentDictionary()
            _ = CGSessionCopyCurrentDictionary()
        }

        let modules = ["duplicates", "uninstaller", "disk"]
        let start = Date()
        for _ in modules { onePerModuleVerdict() }
        let asIs = Date().timeIntervalSince(start)

        // Hoisted: the session dictionary and the power reading do not change
        // within one tick, so read each once and hand the same answer to all
        // three modules.
        let start2 = Date()
        _ = SystemIdle.seconds()
        _ = PowerSource.isOnMains
        _ = CGSessionCopyCurrentDictionary()
        for _ in modules { _ = SystemIdle.seconds() } // idle can genuinely differ call to call
        let hoisted = Date().timeIntervalSince(start2)

        print(String(format: "one tick, 3 modules, as written: %.5f ms", asIs * 1000))
        print(String(format: "one tick, 3 modules, hoisted:    %.5f ms", hoisted * 1000))
        print(String(format: "saved by hoisting: %.5f ms/tick, %.3f ms/hour (60 ticks)",
                     (asIs - hoisted) * 1000, (asIs - hoisted) * 1000 * 60))
    }
}
