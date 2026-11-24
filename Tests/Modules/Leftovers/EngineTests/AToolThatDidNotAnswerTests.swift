import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// **A tool that failed does not read as «nothing is loaded», because empty is
/// the unsafe direction.**
///
/// `systemextensionsctl` and `launchctl` are read with their exit status. An
/// empty list is a claim about this Mac: a launch agent whose label is a live
/// system extension is `inUse` *because* it appears in the list, and with the
/// list empty it would become a leftover, ticked by «Select all» and trashed.
/// The disabled list decides the «Disabled» badge — the module's whole
/// reassurance that a login item will not run. «Nothing is loaded» and «nobody
/// answered» are two facts (Architecture/ModulePattern.md § Ports and logic), and
/// `LeftoversFakeLoaded` holds `nil` as well as `[]`.
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
        return try firstAgent(home: home, files: files, loaded: loaded)
    }

    private var liveExtension: SystemExtensionInfo {
        SystemExtensionInfo(identifier: label, version: "1", enabled: true)
    }

    /// **The guard.** The tool did not answer, and the row is not a leftover.
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
        tailTheLog()

        _ = try agent(when: LeftoversFakeLoaded(installed: nil, disabled: nil))
        let lines = loggedLines("leftovers")

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
