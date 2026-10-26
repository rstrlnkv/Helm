import XCTest
@testable import Module_KeepAwake_Engine

/// `Conditions.resolve` decides both *whether* the Mac is held awake and *which
/// chips the panel draws*. Those are two returns off one switch, and the panel
/// reads the second while the power assertion follows the first — the shape that
/// let a filtered list be deleted elsewhere in this app. Exhaustive over all six
/// flags, because the interesting inputs are the combinations nobody drew.
final class ConditionsInvariantTests: XCTestCase {

    private func allInputs() -> [Conditions.Inputs] {
        (0..<64).map { bits in
            var i = Conditions.Inputs()
            i.manual          = bits & 1 != 0
            i.timerRunning    = bits & 2 != 0
            i.externalDisplay = bits & 4 != 0
            i.onPower         = bits & 8 != 0
            i.appRunning      = bits & 16 != 0
            i.suppressed      = bits & 32 != 0
            return i
        }
    }

    /// The invariant the UI depends on: an active session always names at least
    /// one reason, and naming a reason always means active. A state that is
    /// active with an empty chip row is a menu-bar icon lit for no stated cause;
    /// the reverse is a chip drawn under an idle icon.
    func test_isActive_holds_exactly_when_a_condition_is_named() {
        for i in allInputs() {
            let r = Conditions.resolve(i)
            XCTAssertEqual(r.isActive, !r.conditions.isEmpty, "\(i) -> \(r)")
        }
    }

    /// Every named condition must be traceable to an input that is actually set.
    /// A chip for a display that is unplugged is a lie the user cannot dismiss.
    func test_no_condition_is_named_that_the_inputs_do_not_support() {
        for i in allInputs() {
            let r = Conditions.resolve(i)
            if r.conditions.contains(.manual) { XCTAssertTrue(i.manual, "\(i)") }
            if r.conditions.contains(.timer) { XCTAssertTrue(i.timerRunning, "\(i)") }
            if r.conditions.contains(.externalDisplay) { XCTAssertTrue(i.externalDisplay, "\(i)") }
            if r.conditions.contains(.power) { XCTAssertTrue(i.onPower, "\(i)") }
            if r.conditions.contains(.app) { XCTAssertTrue(i.appRunning, "\(i)") }
        }
    }

    /// `suppressed` means "the user switched it off by hand while an automatic
    /// condition was holding". It is checked *after* the manual/timer branch, so
    /// this pins the rule that the branch order encodes: suppression silences
    /// the automatic reasons and nothing else.
    func test_suppression_only_ever_silences_the_automatic_reasons() {
        for i in allInputs() where i.suppressed {
            let r = Conditions.resolve(i)
            if i.manual || i.timerRunning {
                XCTAssertTrue(r.isActive, "an explicit request was silenced by suppression: \(i)")
            } else {
                XCTAssertFalse(r.isActive, "suppression did not silence the automatic reasons: \(i)")
                XCTAssertTrue(r.conditions.isEmpty, "\(i) -> \(r)")
            }
        }
    }

    /// Clearing suppression may only ever turn the session on, never off — the
    /// switch has one direction. Compares each input against its own twin.
    func test_suppression_is_monotone() {
        for i in allInputs() where i.suppressed {
            var released = i
            released.suppressed = false
            let before = Conditions.resolve(i), after = Conditions.resolve(released)
            XCTAssertTrue(after.conditions.isSuperset(of: before.conditions), "\(i)")
            if before.isActive { XCTAssertTrue(after.isActive, "\(i)") }
        }
    }
}

/// The guard reads one integer with no way to say "I do not know". Worth
/// pinning what it promises, because `IOPSPowerInfo.snapshot()` upstream turns
/// an unreadable capacity into `percent: 0` while still reporting `onBattery`.
final class BatteryGuardInvariantTests: XCTestCase {

    /// Monotone in the reading and in the threshold: a lower charge can never
    /// be safer than a higher one, and raising the threshold can never make a
    /// charge acceptable that was not. Swept across the range plus the values
    /// outside it that IOKit can hand back.
    func test_shouldDeactivate_is_monotone_in_charge_and_threshold() {
        for threshold in [0, 1, 20, 50, 100] {
            var seenTrip = false
            for percent in stride(from: 100, through: -1, by: -1) {
                let trips = BatteryGuard.shouldDeactivate(enabled: true, isOnBattery: true,
                                                          percent: percent, threshold: threshold)
                if seenTrip { XCTAssertTrue(trips, "charge \(percent) vs \(threshold)") }
                seenTrip = seenTrip || trips
            }
            XCTAssertTrue(seenTrip, "threshold \(threshold) never trips, not even at -1%")
        }
    }

    /// Both switches are veto: nothing about the reading can defeat them.
    func test_disabled_or_on_mains_never_trips_for_any_reading() {
        for percent in [-1, 0, 1, 50, 100, 255, Int.max, Int.min] {
            XCTAssertFalse(BatteryGuard.shouldDeactivate(enabled: false, isOnBattery: true,
                                                         percent: percent, threshold: 100))
            XCTAssertFalse(BatteryGuard.shouldDeactivate(enabled: true, isOnBattery: false,
                                                         percent: percent, threshold: 100))
        }
    }
}

/// `sleepDisabled` decides whether Helm undoes a system-wide sleep block it may
/// have set in a previous run. A false positive re-enables sleep on a Mac the
/// user disabled it on themselves; a false negative leaves a clamshell Mac
/// permanently unable to sleep. The fixture is real `pmset -g` output, kept
/// whole rather than reduced to the one line, because the parser is a substring
/// scan over *every* line and the neighbours are what can defeat it.
final class ClamshellPmsetFixtureTests: XCTestCase {

    private let sleepEnabled = """
    System-wide power settings:
     SleepDisabled\t\t0
    Currently in use:
     standby              1
     Sleep On Power Button 1
     hibernatefile        /var/vm/sleepimage
     powernap             1
     networkoversleep     0
     disksleep            10
     sleep                0 (sleep prevented by coreaudiod, powerd, HelmApp)
     hibernatemode        3
     ttyskeepawake        1
     displaysleep         20 (display sleep prevented by HelmApp)
     tcpkeepalive         1
     lowpowermode         0
     womp                 1
    """

    /// Six other lines on this machine carry a `1`, and two of them contain the
    /// word "sleep". None of them may be mistaken for the flag.
    func test_real_output_with_sleep_enabled_reads_as_enabled() {
        XCTAssertFalse(ClamshellRecovery.sleepDisabled(inPmsetOutput: sleepEnabled))
    }

    func test_the_same_output_with_the_flag_set_reads_as_disabled() {
        let disabled = sleepEnabled.replacingOccurrences(of: "SleepDisabled\t\t0",
                                                         with: "SleepDisabled\t\t1")
        XCTAssertTrue(ClamshellRecovery.sleepDisabled(inPmsetOutput: disabled))
    }

    // Note for whoever reads this next: the check is `line.contains("1")`, not
    // a read of the value. It survives today only because no other line names
    // `SleepDisabled` and the flag is never annotated. macOS already annotates
    // the neighbouring `sleep` line ("sleep 0 (sleep prevented by …)"); the day
    // the flag line gets the same treatment, this parser inverts. Not asserted
    // here — that output does not exist yet, and a gate on invented text is a
    // red suite, not a finding.

    /// Nothing to read is not "disabled" — restoring sleep on empty output would
    /// undo a block the user set with pmset by hand.
    func test_empty_and_error_output_never_reads_as_disabled() {
        XCTAssertFalse(ClamshellRecovery.sleepDisabled(inPmsetOutput: ""))
        XCTAssertFalse(ClamshellRecovery.sleepDisabled(inPmsetOutput: "pmset: command not found"))
    }
}
