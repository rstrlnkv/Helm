import CoreGraphics
import XCTest
@testable import HelmRuntime

/// `ScanCoordinator.considerAll` calls `verdict(for:)` once per scannable
/// module (three today: duplicates, uninstaller, disk), and each call reads
/// `SystemIdle.seconds()`, `PowerSource.isOnMains` and — inside it,
/// `ownsTheConsole` and `screenIsLocked` each call `CGSessionCopyCurrentDictionary`
/// separately — twice. So one tick is 3 idle reads, 3 power reads and 6 session
/// reads, none of which change between the calls within one tick: the same
/// answer is fetched, and discarded, per module.
///
/// This measures the primitives directly — `ScanCoordinator` itself lives in
/// the `HelmApp` executable target, which has no test target, so its own
/// `verdict(for:)` cannot be called from here. What is measured is exactly
/// what it calls.
///
/// Report only — `SystemIdle` is already documented at 0.0000 ms warm; this
/// asks whether the two calls this file adds (power, session) change that
/// answer.
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

    /// One tick, as `considerAll` actually drives it: three modules, each
    /// calling `verdict(for:)` which reads idle once, power once, and the
    /// session dictionary twice (`ownsTheConsole`, then `screenIsLocked`).
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
