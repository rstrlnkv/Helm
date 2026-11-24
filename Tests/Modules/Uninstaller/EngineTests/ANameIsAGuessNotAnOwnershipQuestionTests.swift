import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// `scanSync` exempts the name-matched candidates from `LeftoverOwnership`,
/// and the exemption is not a hole: `claims(name:)` looks for the bundle id
/// in the name, a display-name folder carries none, and dropping the
/// `!c.matchedByName` deletes every guess and logs it as another app's.
///
/// So the rule cannot judge a display name, and the scan keeps the guess,
/// unticked. "Is another installed app called this?" is a different question,
/// which nothing on this path reads.
final class ANameIsAGuessNotAnOwnershipQuestionTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("nameguess")
        tailTheLog()
    }

    private let player = InstalledApp(name: "Player", bundleID: "com.acme.player",
                                      path: "/Applications/Player.app")

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
        return await engine.scan(bundleID: player.bundleID, appName: player.name)
    }

    // MARK: -

    /// Asked about a display name, the ownership check answers no: not
    /// "somebody else's" but "not a name I can read".
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

    /// Nor is it logged as somebody else's: a guess never judged is neither a
    /// scan that found nothing nor a refusal.
    func testAGuessIsNotLoggedAsBelongingToAnotherApp() async throws {
        _ = try plantBoth()

        let result = try await scan()

        XCTAssertEqual(result.leftovers.count, 2, "precondition: the scan really ran")
        let lines = loggedLines(UninstallerEngine.moduleID)
        XCTAssertFalse(lines.contains { $0.contains("refused") }, """
            the log blames another app for a candidate nothing judged: \(lines)
            """)
    }
}
