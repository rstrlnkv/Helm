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
/// The assertion is on **the taps' own mach port names**, not on surviving: a
/// use-after-free takes the whole runner down rather than failing a test, and
/// whether the port was handed back is a fact about teardown that no
/// scheduling can fake.
///
/// It used to count the task's whole namespace (`mach_port_names` before and
/// after) against a threshold, and that flaked at about 1 full run in 3 while
/// every tap tore down correctly: the suite process shares one namespace with
/// everything else that lives in it, and `HelmAppTests` bootstraps the real
/// modules through `ModuleHost.shared` — a singleton, so a real `CGKeyTap`
/// and a real spell pipeline stay live for the rest of the suite. Typing
/// anywhere on the machine during this test's window then lands spell-server
/// and AddressBook XPC traffic (each connection a fresh receive right, each
/// retry a fresh name) inside the diff. Measured: one background spell thread
/// alone added 11 names — RECV×3, RECV+SEND×3, SEND×3, PSET×1 — and none of
/// them was a tap. Asking about the specific names the taps held is immune to
/// all of it.
final class KeyTapOutlivesNobodyTests: XCTestCase {

    /// Enough cycles that a real leak is an order of magnitude clear of name
    /// reuse, and few enough to cost nothing.
    private let cycles = 30

    /// Freed mach port names are reused eagerly, so a name that is valid again
    /// later is not proof the tap survived — but a tap that was never torn
    /// down holds its name as a *receive right* for ever, and thirty of them
    /// cannot be impersonated by reuse inside one test. The threshold is the
    /// allowance for reuse, not for leaks.
    private let reuseAllowance = 15

    /// Turns the run loop over so anything the teardown scheduled has run.
    private func settle() {
        for _ in 0..<5 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
    }

    /// Whether this task still holds `name` as a receive right — which is what
    /// a live `CFMachPort` is, and what invalidation gives back.
    private func isReceiveRight(_ name: mach_port_name_t) -> Bool {
        var type: mach_port_type_t = 0
        guard mach_port_type(mach_task_self_, name, &type) == KERN_SUCCESS else { return false }
        // MACH_PORT_TYPE(MACH_PORT_RIGHT_RECEIVE) = 1 << 17; the macro does
        // not import into Swift.
        return type & (1 << 17) != 0
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

        var names: [mach_port_name_t] = []
        for _ in 0..<cycles {
            let tap = CGKeyTap()
            // Asserted, not assumed: a `start` that refused would make the loop
            // below a loop over nothing and this test vacuous.
            XCTAssertTrue(tap.start({ _ in }, onModifier: { _ in }))
            // Recorded while live — after teardown there is nothing to ask.
            // The subject must exist before its absence can mean anything.
            guard let name = tap.portName else {
                XCTFail("a started tap reported no port name"); return
            }
            names.append(name)
            // No `stop()`. `tap` goes out of scope here, which is the whole
            // subject: `ModuleHost.bootstrap()` drops engines exactly this way.
        }
        settle()
        // Unique, because a freed name is eagerly reused by the next cycle's
        // tap: with teardown working this set is small and none of it is still
        // a receive right; with teardown broken nothing is freed, every cycle
        // takes a fresh name, and all thirty are still receive rights.
        let held = Set(names).filter(isReceiveRight)
        XCTAssertLessThanOrEqual(held.count, reuseAllowance,
                                 "\(cycles) taps were dropped and \(held.count) of their mach "
                                 + "port name(s) are still receive rights — each one is a live "
                                 + "tap holding a pointer to a freed CGKeyTap")
    }

    /// And the ordinary route gives the port back too. Without
    /// `CFMachPortInvalidate` the port and the run loop source it caches retain
    /// each other, so `stop()` alone left one behind per start.
    func testStopHandsThePortBack() throws {
        try skipWithoutTheGrant()

        var names: [mach_port_name_t] = []
        for _ in 0..<cycles {
            let tap = CGKeyTap()
            XCTAssertTrue(tap.start({ _ in }, onModifier: { _ in }))
            guard let name = tap.portName else {
                XCTFail("a started tap reported no port name"); return
            }
            names.append(name)
            tap.stop()
        }
        settle()
        let held = Set(names).filter(isReceiveRight)
        XCTAssertLessThanOrEqual(held.count, reuseAllowance,
                                 "\(cycles) taps were stopped and \(held.count) of their mach "
                                 + "port name(s) are still receive rights")
    }

    /// Stopping something that never started, and stopping twice, are both
    /// things `deinit` will do after `deactivate()` already has.
    func testStoppingTwiceIsHarmless() {
        let tap = CGKeyTap()
        tap.stop()
        tap.stop()
    }
}
