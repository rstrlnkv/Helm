import XCTest
@testable import Module_Leftovers_Engine

final class LaunchAgentReaderTests: XCTestCase {
    func testReadsLabelAndProgramFromProgramKey() {
        let plist: [String: Any] = ["Label": "com.vendor.agent",
                                    "Program": "/Applications/Gone.app/Contents/MacOS/helper"]
        let info = LaunchAgentReader.read(plist: plist, path: "/L/com.vendor.agent.plist")
        XCTAssertEqual(info.identifier, "com.vendor.agent")
        XCTAssertEqual(info.program, "/Applications/Gone.app/Contents/MacOS/helper")
    }

    /// Most agents use ProgramArguments; the executable is the first element.
    func testFallsBackToFirstProgramArgument() {
        let plist: [String: Any] = ["Label": "com.vendor.agent",
                                    "ProgramArguments": ["/usr/local/bin/thing", "--daemon"]]
        let info = LaunchAgentReader.read(plist: plist, path: "/L/com.vendor.agent.plist")
        XCTAssertEqual(info.program, "/usr/local/bin/thing")
    }

    /// Without a Label the filename is the identifier — that is the convention
    /// launchd itself documents.
    func testIdentifierFallsBackToTheFilename() {
        let info = LaunchAgentReader.read(plist: [:], path: "/L/com.vendor.other.plist")
        XCTAssertEqual(info.identifier, "com.vendor.other")
        XCTAssertNil(info.program)
    }

    func testKeepsRunAtLoadForDisplay() {
        let info = LaunchAgentReader.read(plist: ["Label": "a.b.c", "RunAtLoad": true],
                                          path: "/L/a.b.c.plist")
        XCTAssertTrue(info.runAtLoad)
    }
}
