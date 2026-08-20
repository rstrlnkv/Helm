import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// **The log carries no names, and in this module the leaf of every path is one.**
///
/// Leftovers' own lines count and never name — but every removal goes through
/// `HelmTrash`, which writes `Redact.path(path)`, and `Redact.path` only replaces the
/// home directory with `~`. That is right for a module whose paths name folders; here
/// the last component is a bundle id (`~/Library/Preferences/com.acme.tool.plist`,
/// `~/Library/LaunchAgents/com.vendor.updater.plist`), which is exactly what
/// `Redact.app` exists for: ARCHITECTURE.md § What must not reach the file says a
/// bundle id names a person's habits.
///
/// And these lines are not the exceptional case. A refusal by Full Disk Access is an
/// ordinary outcome for this module — ARCHITECTURE.md records 23 of 42 launches with
/// it denied — so «trash refused …» is what a person's log fills up with, in the file
/// they attach to a bug report.
///
/// **Nothing here is trashed.** One path is outside the scope, so the engine refuses
/// it before anything is attempted; the other is inside a temporary home and does not
/// exist, so `trashItem` answers «no such file». Both write their line, which is the
/// subject.
final class TheLogDoesNotNameTheSoftwareTests: XCTestCase {

    /// Distinctive enough that finding it in a message cannot be a coincidence, and
    /// shaped like what this module really handles.
    private let bundleID = "com.secret.vendor.tool-\(UUID().uuidString)"
    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("leftovers-log")
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var lines: [String] {
        HelmLog.shared.recentEntries().filter { $0.category == "leftovers" }.map(\.message)
    }

    /// Both refusals a removal can write, in one batch: one path the gate turns away
    /// and one macOS does.
    private func refusals() async -> [String] {
        let outOfScope = home.appendingPathComponent("Documents/\(bundleID).plist").path
        let inScope = home.appendingPathComponent("Library/Preferences/\(bundleID).plist").path
        _ = await LeftoversEngine(home: home, files: LeftoversFakeFiles(),
                                  apps: LeftoversFakeApps(), loaded: LeftoversFakeLoaded(),
                                  switcher: LeftoversFakeSwitcher())
            .trash([outOfScope, inScope])
        return lines
    }

    /// The two lines that are about a path, told from the module's own counting lines
    /// by their prefix — «trashing 1, refused 1 out of scope» also contains
    /// «refused» and names nothing, so counting that one in would make the control
    /// pass without either subject line existing.
    private func aboutAPath(_ written: [String]) -> [String] {
        written.filter {
            $0.hasPrefix("refused out-of-scope path:") || $0.hasPrefix("trash refused ")
        }
    }

    func testARefusalDoesNotNameTheSoftware() async {
        let written = await refusals()

        XCTAssertEqual(aboutAPath(written).count, 2, """
            neither refusal was written, so an assertion about what they contain proves nothing: \
            \(written)
            """)
        XCTAssertFalse(written.contains { $0.contains(bundleID) }, """
            the log names the software somebody has: \(written). The leaf of a path in this module \
            is a bundle id, and `Redact.app` is what the app already uses for one.
            """)
    }

    /// Redacting the name must not cost the line its usefulness: which folder, which
    /// kind of file, and whether two lines are about the same thing are the whole
    /// reason a removal is logged at all.
    func testTheLineStillSaysWhereAndWhatAndWhich() async {
        let written = await refusals()
        let tag = Redact.app(bundleID)

        XCTAssertTrue(written.contains { $0.contains("/Library/Preferences/") }, """
            the folder is gone from the line as well, so nobody can tell a settings file from a \
            launch agent: \(written)
            """)
        XCTAssertTrue(aboutAPath(written).allSatisfy { $0.contains(".plist") },
                      "the kind of file is worth keeping in clear: \(written)")
        XCTAssertEqual(written.filter { $0.contains(tag) }.count, 2, """
            the two lines are about one file and do not say so — a tag is stable on purpose, so \
            that «the same one as three lines up?» stays answerable: \(written)
            """)
    }
}
