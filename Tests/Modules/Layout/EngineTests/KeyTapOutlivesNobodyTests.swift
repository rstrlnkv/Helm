import XCTest
import AppKit
import Darwin.Mach
@testable import Module_Layout_Engine

/// A tap that is let go stops watching the keyboard.
///
/// `CGKeyTap` hands CoreGraphics a **non-owning** pointer to itself, which is
/// the only shape that lets the object be freed while the tap is still live —
/// and a live tap resolving that pointer is a `swift_retain` on freed memory,
/// on the main run loop, inside somebody's typing. It was seen as one SIGSEGV
/// in about six runs of `HelmAppTests`, where a nested run loop spin services a
/// tap whose engine an earlier `bootstrap()` had already replaced.
///
/// The assertion is on **mach port names**, not on surviving: a use-after-free
/// takes the whole runner down rather than failing a test, and whether it does
/// so on any given run is a race. Whether the port was handed back is a fact
/// about teardown that no scheduling can fake. Measured on this machine before
/// the fix: 34 and 35 names left behind over 30 cycles, against a noise floor
/// of 6 and 7 for the same loop with no tap in it.
final class KeyTapOutlivesNobodyTests: XCTestCase {

    /// Every mach port name this task holds. The tap's port is one of them, and
    /// it comes back only when the port is invalidated and released.
    private func portNames() -> Int {
        var names: mach_port_name_array_t?
        var types: mach_port_type_array_t?
        var nameCount: mach_msg_type_number_t = 0
        var typeCount: mach_msg_type_number_t = 0
        guard mach_port_names(mach_task_self_, &names, &nameCount,
                              &types, &typeCount) == KERN_SUCCESS else { return -1 }
        return Int(nameCount)
    }

    /// Enough cycles that the leak is an order of magnitude clear of the noise,
    /// and few enough to cost nothing.
    private let cycles = 30

    /// Turns the run loop over so anything the teardown scheduled has run.
    private func settle() {
        for _ in 0..<5 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
    }

    private func skipWithoutTheGrant() throws {
        let tap = CGKeyTap()
        defer { tap.stop() }
        try XCTSkipUnless(tap.start({ _ in }, onModifier: { _ in }),
                          "no accessibility grant for the test runner — no tap to tear down")
    }

    /// The defect exactly: dropped without anyone calling `stop()`.
    func testATapDroppedWithoutStopHandsItsPortBack() throws {
        try skipWithoutTheGrant()

        let before = portNames()
        for _ in 0..<cycles {
            let tap = CGKeyTap()
            // Asserted, not assumed: a `start` that refused would make the loop
            // below a loop over nothing and this test vacuous.
            XCTAssertTrue(tap.start({ _ in }, onModifier: { _ in }))
            // No `stop()`. `tap` goes out of scope here, which is the whole
            // subject: `ModuleHost.bootstrap()` drops engines exactly this way.
        }
        settle()
        let leaked = portNames() - before
        XCTAssertLessThanOrEqual(leaked, 15,
                                 "\(cycles) taps were dropped and \(leaked) mach port name(s) "
                                 + "stayed behind — each one is a live tap holding a pointer "
                                 + "to a freed CGKeyTap")
    }

    /// And the ordinary route gives the port back too. Without
    /// `CFMachPortInvalidate` the port and the run loop source it caches retain
    /// each other, so `stop()` alone left one behind per start.
    func testStopHandsThePortBack() throws {
        try skipWithoutTheGrant()

        let before = portNames()
        for _ in 0..<cycles {
            let tap = CGKeyTap()
            XCTAssertTrue(tap.start({ _ in }, onModifier: { _ in }))
            tap.stop()
        }
        settle()
        let leaked = portNames() - before
        XCTAssertLessThanOrEqual(leaked, 15,
                                 "\(cycles) taps were stopped and \(leaked) mach port name(s) "
                                 + "stayed behind")
    }

    /// Stopping something that never started, and stopping twice, are both
    /// things `deinit` will do after `deactivate()` already has.
    func testStoppingTwiceIsHarmless() {
        let tap = CGKeyTap()
        tap.stop()
        tap.stop()
    }
}
