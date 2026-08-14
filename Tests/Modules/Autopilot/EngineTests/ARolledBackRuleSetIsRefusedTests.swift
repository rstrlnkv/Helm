import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The rule set the person had yesterday, put back tonight.
///
/// `AutopilotSealTests` covers the rule set somebody *wrote*; this covers the
/// one Helm wrote and nobody has any business running. The pair verifies —
/// Helm really did save it — so the seal says yes, and the plist it lives in is
/// readable by anything running as this user and is in every Time Machine
/// backup. Keeping a copy costs an attacker nothing and putting it back is not
/// tampering by any test the seal alone can make.
///
/// What that buys them: the rule the person deleted, the folder they stopped
/// watching, the destination they moved off the shared disk. Every assertion
/// below is a directory listing or the bytes in the store — a count could be
/// satisfied by the rules never having matched.
final class ARolledBackRuleSetIsRefusedTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var backing: InMemoryKeyValueStore!
    private var namespace: String!
    private var keys: TestRuleKey!
    /// One item on one Mac: every engine in a test is handed this same one.
    private var sequence: TestRuleSequence!
    /// The file the rules take. Unownable and reclaimed, because these rules
    /// really trash: the file leaves the temporary directory for `~/.Trash` on
    /// the machine running the suite, where deleting the temporary directory
    /// reclaims nothing and a cleanup by a plain name would be deleting
    /// somebody's own work.
    private var leaf: String!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        backing = InMemoryKeyValueStore()
        namespace = "autopilot.test.\(UUID().uuidString)"
        keys = TestRuleKey()
        sequence = TestRuleSequence()
        leaf = unownableLeaf("statement.pdf")
        reclaimFromTrash(leaf)
    }

    private func engine() -> AutopilotEngine {
        AutopilotEngine(store: NamespacedStore(namespace: namespace, backing: backing),
                        home: home.path, keys: keys, sequence: sequence)
    }

    private var payloadKey: String { "module.\(namespace!).folders" }
    private var macKey: String { "module.\(namespace!).\(RuleSeal.storeKey)" }
    private var seqKey: String { "module.\(namespace!).\(RuleSeal.sequenceKey)" }

    /// Everything the plist holds about the rules — which is everything an
    /// attacker keeping a copy keeps.
    private func stored() -> [String: Any] {
        [payloadKey: backing.raw[payloadKey] as Any,
         macKey: backing.raw[macKey] as Any,
         seqKey: backing.raw[seqKey] as Any]
    }

    private func putBack(_ copy: [String: Any]) {
        for (key, value) in copy { backing.raw[key] = value }
    }

    /// A rule that empties the folder, so what it did is visible as an absence
    /// and nothing else.
    private func emptyingRules() -> [WatchedFolder] {
        [WatchedFolder(id: "f", path: root.path, enabled: true, rules: [
            Rule(id: "r", name: "take it", enabled: true, match: .all,
                 conditions: [.fileExtension(["pdf"])], action: .trash),
        ], depth: 1)]
    }

    /// The rule set the person replaced it with: same folder, nothing to do.
    private func harmlessRules() -> [WatchedFolder] {
        [WatchedFolder(id: "f", path: root.path, enabled: true, rules: [], depth: 1)]
    }

    private func tree() -> [String] {
        let all = FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String]
        return (all ?? []).sorted()
    }

    private func writeAFile() throws {
        try Data("private".utf8).write(to: root.appendingPathComponent(leaf))
    }

    // MARK: - The control

    /// Without this the refusals below prove nothing: a rule set that never
    /// matched is refused and executed alike.
    func testTheRuleSetSavedThroughHelmRuns() throws {
        try writeAFile()
        let helm = engine()
        helm.folders = emptyingRules()

        helm.sweepAll()

        XCTAssertEqual(tree(), [], "these rules do act on this file when Helm saved them")
    }

    // MARK: - The rule set from before

    /// The measurement: v1 saved, the person edits to v2, the old pair is written
    /// back — and the engine reported the v1 rules with no refusal at all.
    func testAnOlderSealedRuleSetIsNotRun() throws {
        try writeAFile()
        let helm = engine()
        helm.folders = emptyingRules()
        let yesterday = stored()
        helm.folders = harmlessRules()
        XCTAssertEqual(helm.folders.first?.rules.count, 0, "the premise: the person edited them")

        putBack(yesterday)
        helm.sweepAll()

        XCTAssertEqual(tree(), [leaf], "the rule the person deleted ran")
        XCTAssertTrue(helm.folders.isEmpty, "the engine handed the old rules out")
        XCTAssertTrue(helm.rulesRefused, "nothing said the rules on disk are not the person's")
    }

    /// And the number beside the payload cannot be raised to clear the mark: it
    /// is inside the sealed message, so editing it breaks the seal instead.
    func testRaisingTheNumberInThePlistDoesNotRestoreAnOldRuleSet() throws {
        try writeAFile()
        let helm = engine()
        helm.folders = emptyingRules()
        let yesterday = stored()
        helm.folders = harmlessRules()

        putBack(yesterday)
        backing.raw[seqKey] = 99
        helm.sweepAll()

        XCTAssertEqual(tree(), [leaf])
        XCTAssertTrue(helm.rulesRefused)
    }

    /// A refused rule set is not overwritten, whichever refusal it is — the
    /// lesson of the empty page, applied to the one state that is *not*
    /// tampering. What is in the file is a rule set the person once had.
    func testARolledBackRuleSetIsNotWrittenOver() throws {
        let helm = engine()
        helm.folders = emptyingRules()
        let yesterday = stored()
        helm.folders = harmlessRules()
        putBack(yesterday)
        XCTAssertTrue(helm.folders.isEmpty, "the premise: this rule set is refused")

        helm.folders = [WatchedFolder(id: "new", path: root.path, enabled: true,
                                      rules: [], depth: 1)]

        XCTAssertEqual(backing.raw[payloadKey] as? Data, yesterday[payloadKey] as? Data,
                       "a refused rule set was destroyed by the next ordinary save")
    }

    // MARK: - The upgrade

    /// Every Mac that has run Autopilot has a sealed rule set with no number
    /// beside it and no mark to compare it against. Refusing those would be a
    /// build that throws away the rules of everyone who installs it.
    func testARuleSetSealedByAnOlderBuildStillRuns() throws {
        try writeAFile()
        // Exactly what the previous build wrote: the payload, and a MAC over the
        // payload alone.
        let data = try JSONEncoder().encode(emptyingRules())
        backing.raw[payloadKey] = data
        backing.raw[macKey] = SettingSeal.mac(for: data, key: TestRuleKey.material)
        keys = TestRuleKey(established: true)

        let helm = engine()
        XCTAssertFalse(helm.rulesRefused, "the rules of everyone upgrading were refused")
        helm.sweepAll()

        XCTAssertEqual(tree(), [], "the person's own rules stopped working after the upgrade")
    }

    // MARK: - The keychain

    /// A mark that cannot be read is "cannot tell", and unverifiable is refused
    /// in this module rather than assumed — the same answer the key itself gets.
    func testAMarkThatCannotBeReadStopsTheRules() throws {
        try writeAFile()
        let helm = engine()
        helm.folders = emptyingRules()
        XCTAssertEqual(tree(), [leaf], "the premise: nothing has run yet")

        sequence = TestRuleSequence(at: sequence.mark, available: false)
        let deaf = engine()
        deaf.sweepAll()

        XCTAssertEqual(tree(), [leaf])
        XCTAssertTrue(deaf.folders.isEmpty)
        XCTAssertEqual(deaf.refusal, .noKey)
    }

    /// Every save moves the mark, which is what makes the number a count of
    /// saves rather than a label. Asserted as an ordering, not as a value: what
    /// matters is that yesterday's number is below today's.
    func testEverySaveRaisesTheMark() {
        let helm = engine()
        helm.folders = emptyingRules()
        let first = sequence.mark

        helm.folders = harmlessRules()

        XCTAssertNotNil(first)
        XCTAssertGreaterThan(sequence.mark ?? 0, first ?? 0, "two saves share a number")
        XCTAssertEqual(backing.raw[seqKey] as? Int, Int(sequence.mark ?? 0),
                       "the plist and the keychain disagree about which rule set this is")
    }

    /// A keychain that answers a read and refuses a write must not cost the
    /// person a save. The rules are written and run; what is lost is the newest
    /// step of the rollback protection, and that is the right end to fail at.
    func testAMarkThatCannotBeRaisedDoesNotStopTheSave() throws {
        try writeAFile()
        sequence = TestRuleSequence(available: true, writable: false)
        let helm = engine()

        helm.folders = emptyingRules()

        XCTAssertEqual(helm.folders.first?.rules.count, 1, "the save was refused")
        XCTAssertFalse(helm.rulesRefused)
        helm.sweepAll()
        XCTAssertEqual(tree(), [], "the rules the person just saved did not run")
    }
}
