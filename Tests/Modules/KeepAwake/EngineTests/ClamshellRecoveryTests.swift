import XCTest
@testable import Module_KeepAwake_Engine

/// `pmset -g` output, read the way the engine reads it on launch.
///
/// `shouldRestoreSleep` used to sit beside this and was reached only by its own
/// test — the engine writes the same `&&` inline, deliberately, so the second
/// half is not evaluated unless the flag is set (the shell-out is the
/// expensive part). Two answers to one question, one of them unused.
final class ClamshellRecoveryTests: XCTestCase {

    func testItFindsTheDisabledState() {
        XCTAssertTrue(ClamshellRecovery.sleepDisabled(inPmsetOutput: " SleepDisabled 1\n hibernatemode 3"))
        XCTAssertTrue(ClamshellRecovery.sleepDisabled(inPmsetOutput: "sleepdisabled  1"))
    }

    func testItIsNotFooledByTheEnabledState() {
        XCTAssertFalse(ClamshellRecovery.sleepDisabled(inPmsetOutput: " SleepDisabled 0"))
        XCTAssertFalse(ClamshellRecovery.sleepDisabled(inPmsetOutput: ""))
    }

    /// The digit has to be on the same line as the name: a `1` anywhere in the
    /// report is not this setting.
    func testADigitOnAnotherLineIsNotThisSetting() {
        XCTAssertFalse(ClamshellRecovery.sleepDisabled(inPmsetOutput: "SleepDisabled 0\nstandby 1"))
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

    /// Seven lines besides the flag's own carry a `1`, and two of them
    /// (`Sleep On Power Button`, `disksleep`) contain the word "sleep", whatever
    /// its case. None of them may be mistaken for the flag.
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
