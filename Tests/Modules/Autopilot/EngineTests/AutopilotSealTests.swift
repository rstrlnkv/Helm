import Foundation
import XCTest
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The engine reading a rule set it did not write.
///
/// `RuleSealTests` covers the verdict; this covers what the engine *does* with
/// it, over a real folder, because the only statement worth making about a
/// module that moves files unattended is which files are still there
/// afterwards. Every assertion below is a directory listing — a count or a
/// `SweepReport` field can be satisfied by the rules never having matched, and
/// that is exactly the way a fix like this ships inert.
final class AutopilotSealTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var backing: InMemoryKeyValueStore!
    private var namespace: String!
    private var keys: TestRuleKey!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-home-\(UUID().uuidString)")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        backing = InMemoryKeyValueStore()
        namespace = "autopilot.test.\(UUID().uuidString)"
        keys = TestRuleKey()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func engine() -> AutopilotEngine {
        AutopilotEngine(store: NamespacedStore(namespace: namespace, backing: backing),
                        home: home.path, keys: keys)
    }

    // MARK: - The plist, as something else sees it

    private var payloadKey: String { "module.\(namespace!).folders" }
    private var macKey: String { "module.\(namespace!).\(RuleSeal.storeKey)" }

    /// What an attacker does: encode a rule set and write it straight into the
    /// preferences. No Helm involved, no keychain, no TCC grant of its own.
    private func plant(_ folders: [WatchedFolder]) throws {
        backing.raw[payloadKey] = try JSONEncoder().encode(folders)
    }

    /// A rule that empties the folder — the reviewer's demonstration, shrunk to
    /// one file. `.trash` rather than `.move` because what it did is then
    /// visible as an absence and nothing else.
    private func emptyingRules() -> [WatchedFolder] {
        [WatchedFolder(id: "planted", path: root.path, enabled: true, rules: [
            Rule(id: "r", name: "take it", enabled: true, match: .all,
                 conditions: [.fileExtension(["pdf"])], action: .trash),
        ], depth: 1)]
    }

    private func tree() -> [String] {
        let all = FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String]
        return (all ?? []).sorted()
    }

    private func writeAFile() throws {
        try Data("private".utf8).write(to: root.appendingPathComponent("statement.pdf"))
    }

    // MARK: - The control

    /// The rules used by every test below, run the way they are supposed to be
    /// reached: saved through Helm. Without this the refusals prove nothing —
    /// a rule that never matched is refused and executed alike.
    func testRulesSavedThroughHelmStillRun() throws {
        try writeAFile()
        let helm = engine()
        helm.folders = emptyingRules()

        helm.sweepAll()

        XCTAssertEqual(tree(), [], "the rules do act on this file when Helm saved them")
    }

    func testSavingRulesAndReadingThemBackRoundTrips() {
        let helm = engine()
        let saved = emptyingRules()

        helm.folders = saved

        XCTAssertEqual(helm.folders.map(\.id), saved.map(\.id))
        XCTAssertEqual(helm.folders.first?.rules.map(\.id), saved.first?.rules.map(\.id))
        XCTAssertNotNil(backing.raw[macKey] as? String, "saving left no seal to check next time")
    }

    // MARK: - Planted rules

    /// The defect. A process with no permissions of its own writes a rule set
    /// into the plist and waits an hour for Helm to carry the file out.
    func testAPlantedRuleSetIsNotRun() throws {
        try writeAFile()
        try plant(emptyingRules())
        keys = TestRuleKey(established: true)

        let helm = engine()
        helm.sweepAll()

        XCTAssertEqual(tree(), ["statement.pdf"], "a planted rule ran")
        XCTAssertTrue(helm.folders.isEmpty, "the engine handed the planted rules out")
        XCTAssertTrue(helm.rulesRefused)
    }

    /// The subtler edit: Helm's own rule set, with one rule's action changed in
    /// the file. The seal beside it is left alone, because the writer cannot
    /// produce a new one.
    func testRulesEditedInThePlistAreNotRun() throws {
        try writeAFile()
        let helm = engine()
        helm.folders = [WatchedFolder(id: "planted", path: root.path, enabled: true,
                                      rules: [], depth: 1)]

        try plant(emptyingRules())
        helm.sweepAll()

        XCTAssertEqual(tree(), ["statement.pdf"], "the edited rule ran")
        XCTAssertTrue(helm.rulesRefused)
    }

    /// And a seal cannot be moved onto a different rule set either: the MAC
    /// from one payload does not authenticate another.
    func testASealTakenFromAnotherRuleSetDoesNotTravel() throws {
        try writeAFile()
        let helm = engine()
        helm.folders = [WatchedFolder(id: "harmless", path: root.path, enabled: true,
                                      rules: [], depth: 1)]
        let stolen = backing.raw[macKey]

        try plant(emptyingRules())
        backing.raw[macKey] = stolen
        helm.sweepAll()

        XCTAssertEqual(tree(), ["statement.pdf"])
    }

    // MARK: - The upgrade

    /// Somebody who has been using Autopilot has rules and no seal. Refusing
    /// them would throw away configuration they built by hand, which is a worse
    /// defect than the one being fixed — so the first run of this build adopts
    /// what it finds and seals it.
    func testRulesFromBeforeTheSealAreAdoptedOnceAndThenSealed() throws {
        try writeAFile()
        try plant(emptyingRules())

        let helm = engine()
        XCTAssertEqual(helm.folders.map(\.id), ["planted"], "an existing rule set was destroyed")
        XCTAssertFalse(helm.rulesRefused)
        helm.sweepAll()

        XCTAssertEqual(tree(), [], "the person's own rules stopped working after the upgrade")
        XCTAssertNotNil(backing.raw[macKey] as? String, "adopted and not sealed: it will be refused next launch")
    }

    /// The weakness of trust on first use, contained. Adoption is one shot per
    /// installation — the key existing is what says the first run has happened
    /// — so deleting the seal from the plist does not put the engine back into
    /// migration. Without this latch the attack is unchanged: write rules,
    /// delete `foldersMAC`, wait an hour.
    func testDeletingTheSealDoesNotReopenTheMigration() throws {
        try writeAFile()
        try plant([WatchedFolder(id: "planted", path: root.path, enabled: true,
                                 rules: [], depth: 1)])
        let helm = engine()
        XCTAssertEqual(helm.folders.map(\.id), ["planted"], "the premise: these were adopted")

        try plant(emptyingRules())
        backing.raw[macKey] = nil
        helm.sweepAll()

        XCTAssertEqual(tree(), ["statement.pdf"], "deleting the seal re-armed the migration")
        XCTAssertTrue(helm.rulesRefused)
    }

    // MARK: - No key at all

    /// A keychain that will not answer — locked at login is the reachable case.
    /// Unverifiable is refused, not assumed: the module does nothing until it
    /// can tell whose rules these are.
    func testRulesAreNotRunWhileTheKeyIsUnavailable() throws {
        try writeAFile()
        try plant(emptyingRules())
        keys = TestRuleKey(available: false)

        let helm = engine()
        helm.sweepAll()

        XCTAssertEqual(tree(), ["statement.pdf"])
        XCTAssertTrue(helm.folders.isEmpty)
    }

    /// And a save with no key available is refused rather than written
    /// unsealed, which the next launch would read as tampering and throw away.
    func testSavingWithNoKeyKeepsTheOldRulesRatherThanWritingAnUnsealedSet() throws {
        keys = TestRuleKey(available: false)
        let helm = engine()

        helm.folders = emptyingRules()

        XCTAssertNil(backing.raw[payloadKey], "an unsealed rule set was written to the plist")
    }
}
