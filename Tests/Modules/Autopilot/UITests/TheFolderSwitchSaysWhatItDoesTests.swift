import HelmTestSupport
import XCTest
@testable import Module_Autopilot_UI

/// A control's accessibility label is its *name*, and a bare path is not one.
///
/// The folder header's switch was announced as `~/Downloads` — the same string
/// the `Text` beside it already reads — so VoiceOver said the path twice and
/// never what the switch does. Read off the source the way
/// `EveryRowReachesWithoutAMouseTests` reads its rule, and for the same reason:
/// the gap is invisible to whoever is holding the mouse.
final class TheFolderSwitchSaysWhatItDoesTests: XCTestCase {

    func testNoControlInAutopilotIsNamedByABarePath() throws {
        var offenders: [String] = []
        for file in try RepoSource.swiftFiles(under: "Sources/Modules/Autopilot/UI") {
            let lines = try RepoSource.text(of: file).components(separatedBy: "\n")
            for (index, line) in lines.enumerated()
            where line.contains(".accessibilityLabel(Redact.path(") {
                offenders.append("\((file as NSString).lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertEqual(offenders, [], """
            These controls are announced as a bare path, which never says what \
            the control does. Name the control and let the path say which one:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The scan has to be reading the page the rule is about — a check that has
    /// stopped seeing its subject passes forever.
    func testTheScanReadsThePageTheRuleIsAbout() throws {
        let files = try RepoSource.swiftFiles(under: "Sources/Modules/Autopilot/UI")
        XCTAssertTrue(files.contains { $0.hasSuffix("AutopilotSettingsPage.swift") })
    }
}
