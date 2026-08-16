import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// **`scanSync` exempts the name-matched candidates from `LeftoverOwnership`,
/// and that line had nothing under it.** A survey read the exemption as a hole —
/// "the name-matched candidates get no ownership check at all" — and the
/// smallest way to close a hole is to delete the `!c.matchedByName`. Measured
/// here first: dropping it does not add a check, it deletes the feature.
/// `Application Support/Player` disappears from the scan entirely, because
/// `claims(name:)` asks whether the app's **bundle id** occurs in the entry
/// name bounded by dots, and a folder named after a display name carries no id
/// at all — and the refusal is then written to the log as a candidate
/// "belonging to another installed app", which is a sentence about nobody.
///
/// Two facts, so that the next person reading that line is told what it costs
/// rather than left to work it out: the pure rule cannot judge a display name,
/// and the scan's own answer keeps the guess — unticked, for
/// `UninstallPlan.defaultSelection` to leave out and the row to badge.
///
/// What the survey actually wanted is a different question — "is another
/// installed app called this?" — answerable only from the installed apps'
/// display names, which nothing on this path reads today.
final class ANameIsAGuessNotAnOwnershipQuestionTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("nameguess")
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private let player = InstalledApp(name: "Player", bundleID: "com.acme.player",
                                      path: "/Applications/Player.app", sizeBytes: 0)

    /// One folder named after the app, one named after its id — the two kinds of
    /// candidate, with the same app behind them.
    private func plantBoth() throws -> (byName: String, byID: String) {
        let library = home.appendingPathComponent("Library")
        let byName = library.appendingPathComponent("Application Support/Player")
        let byID = library.appendingPathComponent("Caches/com.acme.player")
        for dir in [byName, byID] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(count: 1_000).write(to: dir.appendingPathComponent("blob.bin"))
        }
        return (byName.path, byID.path)
    }

    private func scan() async throws -> ScanResult {
        let engine = UninstallerEngine(home: home, apps: FakeApps(apps: [player]),
                                       fs: FMFileSystem(), trash: FakeTrash(),
                                       running: FakeRunning(running: []))
        return try await engine.scan(bundleID: player.bundleID, appPath: player.path,
                                     appName: player.name)
    }

    // MARK: -

    /// The rule the exemption exists for: asked about a display name, the
    /// ownership check answers **no** — not "this is somebody else's", but "this
    /// is not a name I can read". Putting the name-matched candidates through it
    /// therefore removes every one of them.
    func testTheOwnershipRuleCannotJudgeANameThatCarriesNoID() {
        let owner = LeftoverOwnership(bundleID: player.bundleID,
                                      installedBundleIDs: [player.bundleID],
                                      installedPaths: [player.path],
                                      knownToSystem: { _ in false })
        XCTAssertTrue(owner.claims(name: player.bundleID),
                      "precondition: the rule does claim what it can read")
        XCTAssertFalse(owner.claims(name: player.name), """
            «\(player.name)» is the app's own display name and the rule says no to it, \
            so applying the rule to name-matched candidates deletes them
            """)
    }

    /// And the scan keeps the guess: found, marked as one, and left out of what
    /// arrives ticked.
    func testAFolderNamedAfterTheAppIsOfferedAsAGuessAndNotPreselected() async throws {
        let planted = try plantBoth()

        let result = try await scan()

        let found = Dictionary(uniqueKeysWithValues: result.leftovers.map { ($0.path, $0) })
        XCTAssertNotNil(found[planted.byID], "precondition: the id-named folder was found")
        guard let guess = found[planted.byName] else {
            return XCTFail("""
                the folder named after the app is gone from the scan: \
                \(result.leftovers.map(\.path))
                """)
        }
        XCTAssertTrue(guess.matchedByName, "it must carry the mark the «guess» badge is drawn from")
        let ticked = UninstallPlan.defaultSelection([
            UninstallGroup(app: player, leftovers: result.leftovers, running: false),
        ])
        XCTAssertEqual(ticked, [planted.byID],
                       "a guess must not arrive ticked, and the id-named folder must")
    }

    /// Nor is it written up as somebody else's. The refusal line exists so a
    /// person reading the log can tell a scan that found nothing from one that
    /// was refused; a guess that was never judged is neither.
    func testAGuessIsNotLoggedAsBelongingToAnotherApp() async throws {
        _ = try plantBoth()

        let result = try await scan()

        XCTAssertEqual(result.leftovers.count, 2, "precondition: the scan really ran")
        let lines = HelmLog.shared.recentEntries()
            .filter { $0.category == UninstallerEngine.moduleID }
            .map(\.message)
        XCTAssertFalse(lines.contains { $0.contains("refused") }, """
            the log blames another app for a candidate nothing judged: \(lines)
            """)
    }
}
