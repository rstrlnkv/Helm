import Foundation
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// **A tool that failed reads as «nothing is loaded», and empty is the unsafe
/// direction.**
///
/// `ActiveExtensions.installedExtensions()` and `.disabledLabels()` ran
/// `systemextensionsctl` and `launchctl` and kept only the output, dropping the exit
/// status — so a tool that could not run answered `[]`, and `[]` is a claim about
/// this Mac. What that claim decides: a launch agent whose label is a live system
/// extension is `inUse` *because* it appears in that list, and with the list empty it
/// becomes a leftover, ticked by «Select all» and trashed with the batch. The
/// disabled list decides the «Disabled» badge — this module's whole reassurance that
/// a login item will not run.
///
/// The family CLAUDE.md names: a local reading standing in for a live external fact,
/// with no channel from the port that knows. Two facts, «nothing is loaded» and
/// «nobody answered», and nothing could tell them apart — including a test, which is
/// why `LeftoversFakeLoaded` now holds `nil` as well.
final class AToolThatDidNotAnswerTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    /// A launch agent whose only claim to being in use is the extension list: its
    /// label is an extension identifier, and the program it names is really gone.
    private let label = "com.vendor.security.ext"

    private func agent(when loaded: LeftoversFakeLoaded) throws -> StaleItem {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["\(label).plist"]
        files.plists["/Users/x/Library/LaunchAgents/\(label).plist"] =
            PlistData(["Label": label, "RunAtLoad": true])
        let items = LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(),
                                     extensions: loaded).scan()
        return try XCTUnwrap(items.first { $0.kind == .launchAgent },
                             "precondition: the agent is listed at all")
    }

    private var liveExtension: SystemExtensionInfo {
        SystemExtensionInfo(identifier: label, teamID: "T", name: "Security", version: "1",
                            state: "activated enabled", enabled: true)
    }

    /// **The finding.** The tool did not answer, and the row is a leftover.
    func testNothingIsPromotedToALeftoverWhenTheExtensionListDidNotAnswer() throws {
        let item = try agent(when: LeftoversFakeLoaded(installed: nil))

        XCTAssertEqual(item.status, .undetermined, """
            `systemextensionsctl` did not answer, and the scan read that as «no extensions are \
            loaded on this Mac» — so «\(label)», which is a live system extension, came back \
            \(item.status.rawValue). A verdict may not rest on a reading that did not happen.
            """)
        XCTAssertFalse(item.removable, "and «Select all» ticks it")
    }

    /// The control that makes the assertion above about the *reading* and not about
    /// the rule: when the tool answers and the extension is there, the row is in use.
    func testTheSameAgentIsInUseWhenTheToolAnswersWithIt() throws {
        let item = try agent(when: LeftoversFakeLoaded(installed: [liveExtension]))

        XCTAssertEqual(item.status, .inUse)
        XCTAssertFalse(item.removable)
    }

    /// And the other control: a tool that answers with an empty list really does mean
    /// nothing is loaded, and then the agent is the leftover this module exists for.
    func testTheSameAgentIsALeftoverWhenTheToolAnswersWithNothing() throws {
        let item = try agent(when: LeftoversFakeLoaded(installed: []))

        XCTAssertEqual(item.status, .orphaned)
        XCTAssertTrue(item.removable, "a fix that keeps the module from finding anything is no fix")
    }

    /// Only what the reading decides. `~/Library/Preferences` and the plug-in folders
    /// are judged against installed *apps*, and the extension list never enters into
    /// it — so a silent tool must not grey out the rest of the scan either.
    func testAPreferenceIsStillJudgedWhenTheExtensionListDidNotAnswer() throws {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/Preferences"] = ["com.gone.vendor.app.plist"]
        let items = LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(),
                                     extensions: LeftoversFakeLoaded(installed: nil)).scan()

        XCTAssertEqual(items.first?.status, .orphaned)
        XCTAssertTrue(try XCTUnwrap(items.first).removable)
    }

    /// A reading that did not happen is in the log, by kind and by nothing else —
    /// this is the only place it can be seen from outside, since the row it produces
    /// looks like any other unjudged row.
    func testTheRefusalsAreLoggedAndNameNothing() throws {
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
        defer {
            HelmLog.shared.clearTail()
            HelmLog.shared.setEnabled(false)
        }

        _ = try agent(when: LeftoversFakeLoaded(installed: nil, disabled: nil))
        let lines = HelmLog.shared.recentEntries()
            .filter { $0.category == "leftovers" }.map(\.message)

        XCTAssertTrue(lines.contains { $0.contains("systemextensionsctl") }, """
            nothing said the extension list never came, so the only trace of it is rows that \
            silently changed meaning: \(lines)
            """)
        XCTAssertTrue(lines.contains { $0.contains("launchctl") },
                      "nor that the disabled list never came: \(lines)")
        XCTAssertFalse(lines.contains { $0.contains(label) },
                       "the log names the software: \(lines)")
    }
}
