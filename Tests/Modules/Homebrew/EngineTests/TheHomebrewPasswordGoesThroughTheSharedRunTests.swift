import XCTest
import HelmTestSupport

/// Homebrew's password dialog runs through `PrivilegedRun`, or a cancel reads as
/// a failed `mkdir` again.
///
/// The bare `osascript` this module used to run sends `(-128)` — the only
/// reliable sign of a cancelled dialog — to the standard error `HelmProcess`
/// discards, so every «Cancel» arrived as a status of 1 and the page drew a red
/// «Failed». `PrivilegedRun` owns `-s o` and the reading of that number, and a
/// fake cannot see this: the port's real body is the one thing no test can run
/// without raising the dialog. So it is a reading of the source, with the two
/// halves that make it a check that can fail — the subject was found, and the
/// old spelling is absent from code (comments blanked, so this file's own prose
/// and the port's doc comment cannot satisfy or trip it).
final class TheHomebrewPasswordGoesThroughTheSharedRunTests: XCTestCase {

    func testTheRealRunnerAsksThroughTheSharedRunAndNotThroughABareOsascript() throws {
        let path = "Sources/Modules/Homebrew/Engine/SystemPorts.swift"
        // Comments blanked and literals kept: `osascript` is a string in the old
        // spelling, and `code` would have blanked it.
        let source = SwiftSource.uncommented(try RepoSource.text(of: path))
        let start = try XCTUnwrap(source.range(of: "struct OSAPrivilegedRunner"),
                                  "OSAPrivilegedRunner is not in \(path) — the guard has nothing to read")
        let rest = source[start.lowerBound...]
        let end = rest.range(of: "// MARK:")?.lowerBound ?? rest.endIndex
        let runner = String(rest[..<end])
        XCTAssertTrue(runner.contains("runAdmin"), "the read did not reach the runner's method: \(runner)")
        XCTAssertTrue(runner.contains("PrivilegedRun.run("),
                      "the password dialog no longer goes through PrivilegedRun: \(runner)")
        XCTAssertFalse(runner.contains("osascript"),
                       "a bare osascript is back in Homebrew's password dialog, and with it a cancel that reads as a failure")
    }
}
