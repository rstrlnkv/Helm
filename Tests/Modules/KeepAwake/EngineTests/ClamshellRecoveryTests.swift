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
