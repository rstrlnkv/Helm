import XCTest
@testable import Module_Leftovers_Engine

/// `launchctl print-disabled gui/<uid>` is how macOS itself remembers which
/// login items the user switched off — the setting survives reboots and needs
/// no admin, which is why Helm uses it instead of moving anyone's files.
final class LaunchctlDisabledTests: XCTestCase {
    private let sample = """
    \tdisabled services = {
    \t\t"net.freemacsoft.AppCleaner-SmartDelete" => enabled
    \t\t"com.apple.ManagedClientAgent.enrollagent" => disabled
    \t\t"com.microsoft.update.agent" => enabled
    \t\t"com.acme.helper" => disabled
    \t}
    """

    func testOnlyDisabledLabelsAreReturned() {
        XCTAssertEqual(LaunchctlDisabled.parse(sample),
                       ["com.apple.ManagedClientAgent.enrollagent", "com.acme.helper"])
    }

    func testEmptyOutput() {
        XCTAssertTrue(LaunchctlDisabled.parse("").isEmpty)
        XCTAssertTrue(LaunchctlDisabled.parse("disabled services = {\n}").isEmpty)
    }

    /// The command fails on some systems; garbage must read as "nothing is
    /// disabled" rather than crashing or inventing labels.
    func testGarbageIsIgnored() {
        XCTAssertTrue(LaunchctlDisabled.parse("Could not print domain: 113").isEmpty)
    }
}
