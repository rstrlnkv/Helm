import XCTest
@testable import Module_KeepAwake_Engine

final class ClamshellRecoveryTests: XCTestCase {
    func test_flag_set_and_pmset_disabled_restores() {
        XCTAssertTrue(ClamshellRecovery.shouldRestoreSleep(guardFlagSet: true, pmsetShowsDisabled: true))
    }
    func test_flag_not_set_does_not_restore() {
        XCTAssertFalse(ClamshellRecovery.shouldRestoreSleep(guardFlagSet: false, pmsetShowsDisabled: true))
    }
    func test_flag_set_but_pmset_enabled_does_not_restore() {
        XCTAssertFalse(ClamshellRecovery.shouldRestoreSleep(guardFlagSet: true, pmsetShowsDisabled: false))
    }
    func test_parses_sleepdisabled_1_with_tabs() {
        XCTAssertTrue(ClamshellRecovery.sleepDisabled(inPmsetOutput: " SleepDisabled\t\t1"))
    }
    func test_parses_sleepdisabled_0_as_false() {
        XCTAssertFalse(ClamshellRecovery.sleepDisabled(inPmsetOutput: "SleepDisabled 0"))
    }
    func test_parses_sleepdisabled_1_among_other_lines() {
        XCTAssertTrue(ClamshellRecovery.sleepDisabled(inPmsetOutput: "hibernatemode 3\n SleepDisabled\t\t1"))
    }
}
