import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// **The refusal must not be the thing that destroys the rules.**
///
/// `AutopilotSealTests` proves the seal refuses a rule set something else wrote.
/// This is about the moment after that: `folders` answers `[]`, the page draws
/// its "no folders yet" empty state, and the next ordinary gesture — «Add
/// folder…» — hands the engine a list of one, which `save` wrote over the
/// person's real rules and sealed with Helm's own key. Measured before this
/// existed: a payload of two folders and two rules became one folder and none,
/// with the warning cleared by the same call.
///
/// The rules are not recoverable — one plist key, one payload, no copy — and the
/// person it happens to is the one whose rules were tampered with, which is the
/// case the seal exists for.
///
/// **Every assertion here is about the payload that is still on disk**, decoded
/// back into rules and named, rather than about its size: a byte count can be
/// satisfied by a write that landed and happened to be the same length, and the
/// question is whether the person's rules are still there.
final class ARefusedRuleSetIsNotOverwrittenTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var backing: InMemoryKeyValueStore!
    private var namespace: String!
    private var keys: TestRuleKey!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        backing = InMemoryKeyValueStore()
        namespace = "autopilot.test.\(UUID().uuidString)"
        keys = TestRuleKey()
    }

    private func engine() -> AutopilotEngine {
        AutopilotEngine(store: NamespacedStore(namespace: namespace, backing: backing),
                        home: home.path, keys: keys, sequence: TestRuleSequence())
    }

    private var payloadKey: String { "module.\(namespace!).folders" }

    /// The rules the person wrote: two folders, two rules, the shape the survey
    /// measured.
    private func theirRules() -> [WatchedFolder] {
        [WatchedFolder(id: "downloads", path: root.path, enabled: true, rules: [
            Rule(id: "invoices", name: "Invoices", enabled: true, match: .all,
                 conditions: [.name(.contains, "invoice")], action: .sortIntoSubfolder(.kind)),
        ], depth: 1),
         WatchedFolder(id: "desktop", path: home.appendingPathComponent("Desktop").path,
                       enabled: true, rules: [
                        Rule(id: "shots", name: "Screenshots", enabled: true, match: .all,
                             conditions: [.name(.beginsWith, "Screenshot")],
                             action: .sortIntoSubfolder(.month)),
                       ], depth: 1)]
    }

    /// What the page sends after «Add folder…» on a screen that says there are
    /// none: the list it was handed, with one appended.
    private func onePress() -> [WatchedFolder] {
        [WatchedFolder(id: "fresh", path: root.path, enabled: true, rules: [], depth: 1)]
    }

    /// The rules as they can still be read out of the plist, by their ids —
    /// which is the question "are the person's rules still there".
    ///
    /// A payload that will not decode is named rather than folded into `[]`: the
    /// two are the same list and opposite answers, and one of them means this
    /// test is measuring its own fixture.
    private func storedRuleIDs() -> [String] {
        guard let data = backing.raw[payloadKey] as? Data else { return [] }
        guard let folders = try? JSONDecoder().decode([WatchedFolder].self, from: data)
        else { return ["<the payload no longer decodes>"] }
        return folders.flatMap { $0.rules.map(\.id) }.sorted()
    }

    /// One byte of the payload rewritten, as any process running as the user can
    /// rewrite the plist. The rules stay readable — this is the audit's case,
    /// where the person's rules are still in the file and only the seal has
    /// stopped fitting.
    ///
    /// **Inside a value the person wrote, and named rather than found.** This
    /// flipped the first `I` in the payload, which is a byte whose *meaning*
    /// changes with the JSON key order — and `JSONEncoder` writes a synthesized
    /// `Codable`'s keys in hash order, which Swift seeds per process. So one run
    /// in three struck `sortIntoSubfolder`, the rules stopped decoding, and the
    /// assertion that the person's rules survived read the undecodable payload as
    /// no rules at all.
    private func tamper() throws {
        let data = try XCTUnwrap(backing.raw[payloadKey] as? Data)
        let text = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        let name = try XCTUnwrap(text.range(of: "\"Invoices\""),
                                 "the fixture no longer holds the name this rewrites")
        backing.raw[payloadKey] = Data(text.replacingCharacters(in: name,
                                                                with: "\"Jnvoices\"").utf8)
    }

    // MARK: - The control

    /// **Asserted first, because everything below is about a write that must not
    /// happen.** A test of an absence passes when the subject never happened at
    /// all, so this is the same gesture with nothing tampered with: it lands.
    func testTheSameGestureOverHelmsOwnRulesLands() throws {
        let helm = engine()
        helm.folders = theirRules()
        XCTAssertEqual(storedRuleIDs(), ["invoices", "shots"], "precondition: the rules were saved")

        helm.folders = onePress()

        XCTAssertEqual(helm.folders.map(\.id), ["fresh"],
                       "a save over rules Helm itself sealed was refused")
        XCTAssertEqual(storedRuleIDs(), [],
                       "and the plist still holds the rules the new list replaced")
    }

    // MARK: - The refusal

    func testOnePressAfterTamperingDoesNotWriteOverTheRules() throws {
        let helm = engine()
        helm.folders = theirRules()
        try tamper()

        // A fresh engine, as the next launch builds one: it reads the rules,
        // refuses them, and the page draws an empty list.
        keys = TestRuleKey(established: true)
        let next = engine()
        XCTAssertEqual(next.folders.map(\.id), [], "precondition: the tampered set is refused")
        XCTAssertTrue(next.rulesRefused, "precondition: and the engine knows why")

        next.folders = onePress()

        XCTAssertEqual(storedRuleIDs(), ["invoices", "shots"],
                       "one press destroyed the rules the person wrote, unrecoverably")
    }

    /// And the warning is not cleared by the write that was refused. `save` ends
    /// with `refusing(nil)` — "whatever was in the file before, these are Helm's
    /// now" — which is true of a save that happened and a lie about one that did
    /// not.
    func testTheWarningSurvivesTheRefusedWrite() throws {
        let helm = engine()
        helm.folders = theirRules()
        try tamper()
        keys = TestRuleKey(established: true)
        let next = engine()
        // The page's own first act, and what makes the engine judge the plist:
        // `AutopilotViewModel.load` asks for the folders.
        XCTAssertEqual(next.folders.map(\.id), [], "precondition: the tampered set is refused")
        XCTAssertTrue(next.rulesRefused, "precondition: and the engine knows why")

        next.folders = onePress()

        XCTAssertTrue(next.rulesRefused,
                      "the refused write took the only warning the person gets with it")
    }

    /// The way out, and the only one: an explicit discard. Without it the page
    /// is a screen that will not take an edit for ever.
    func testDiscardingTheRefusedRulesIsTheOneWayPast() throws {
        let helm = engine()
        helm.folders = theirRules()
        try tamper()
        keys = TestRuleKey(established: true)
        let next = engine()
        // The page's own first act, and what makes the engine judge the plist:
        // `AutopilotViewModel.load` asks for the folders.
        XCTAssertEqual(next.folders.map(\.id), [], "precondition: the tampered set is refused")
        XCTAssertTrue(next.rulesRefused, "precondition: and the engine knows why")

        next.discardRefusedRules()

        XCTAssertFalse(next.rulesRefused, "the discard left the engine still refusing")
        next.folders = onePress()
        XCTAssertEqual(next.folders.map(\.id), ["fresh"], "and the page still cannot save")
        XCTAssertEqual(storedRuleIDs(), [], "the discarded set was not replaced")
    }

    /// A keychain that will not answer is the other refusal, and discarding is
    /// not the answer to it: the rules may be perfectly good and unreadable for
    /// the length of a locked login keychain. `save` already refuses; what this
    /// pins is that the two refusals are not one.
    func testAKeyThatCannotBeReadIsADifferentRefusal() throws {
        let helm = engine()
        helm.folders = theirRules()
        keys = TestRuleKey(available: false)

        let next = engine()
        XCTAssertEqual(next.folders.map(\.id), [], "precondition: nothing runs without the key")

        XCTAssertEqual(next.refusal, .noKey, "an unreadable key was reported as tampering")
        XCTAssertEqual(storedRuleIDs(), ["invoices", "shots"], "the rules were touched")
    }
}
