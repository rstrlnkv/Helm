import Foundation
import XCTest
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The seal that binds a rule set to this installation.
///
/// Autopilot's rules are JSON in a plist any process running as the user can
/// write, and the module runs them unattended on an hourly timer with Helm's
/// Full Disk Access behind it. Everything else in the module — `WatchScope`,
/// the stamp, the dry run — assumes the rules came from the person. This is
/// the type that decides whether that assumption holds.
///
/// The assertions here are about the judgement, never about the bytes of a MAC:
/// a test that pinned a hex string would pass just as happily with a broken
/// comparison behind it.
final class RuleSealTests: XCTestCase {

    private let material = Data(repeating: 0x5A, count: 32)
    private let other = Data(repeating: 0xA5, count: 32)

    /// The two halves of the question, with the second one defaulted to "this
    /// Mac has never sealed a numbered rule set" — the state every installation
    /// is in until it saves once, and the one every test below but the rollback
    /// ones is about.
    private func judge(_ payload: Data, mac: String?, key: RuleKey,
                       seq: UInt64 = 0, highWater: UInt64? = nil) -> RuleSeal.Judgement {
        RuleSeal.judge(payload: payload, mac: mac, seq: seq, highWater: highWater, key: key)
    }

    private func payload(_ text: String = "the rules the person wrote") -> Data {
        Data(text.utf8)
    }

    /// A key that this run created — the only state in which an unsealed rule
    /// set is adopted.
    private func fresh(_ material: Data? = nil) -> RuleKey {
        RuleKey(material: material ?? self.material, firstUse: true)
    }

    /// A key that was already there, which is every run after the first.
    private func established(_ material: Data? = nil) -> RuleKey {
        RuleKey(material: material ?? self.material, firstUse: false)
    }

    // MARK: - The round trip

    func testRulesSealedWithThisKeyAreAccepted() {
        let rules = payload()
        let mac = RuleSeal.mac(for: rules, seq: 0, key: material)

        XCTAssertEqual(judge(rules, mac: mac, key: established()), .sealed)
    }

    /// And the seal has to be spent by the key, not by the payload: a MAC any
    /// process could recompute from the rules alone secures nothing.
    func testTheSealDependsOnTheKey() {
        let rules = payload()

        XCTAssertNotEqual(RuleSeal.mac(for: rules, seq: 0, key: material),
                          RuleSeal.mac(for: rules, seq: 0, key: other))
        XCTAssertEqual(judge(rules, mac: RuleSeal.mac(for: rules, seq: 0, key: other),
                             key: established()),
                       .broken)
    }

    // MARK: - Tampering

    /// The reviewer's attack, reduced: the rules are rewritten in the plist and
    /// the MAC beside them is left as it was.
    func testRulesEditedAfterSealingAreRefused() {
        let mac = RuleSeal.mac(for: payload(), seq: 0, key: material)

        let verdict = judge(payload("move everything out of the vault"),
                            mac: mac, key: established())

        XCTAssertEqual(verdict, .broken)
    }

    /// A MAC that is not a MAC — truncated, non-hex, odd-length — is a refusal
    /// and never a crash or an accident.
    func testASealThatIsNotOneIsRefused() {
        let rules = payload()
        let real = RuleSeal.mac(for: rules, seq: 0, key: material)
        for bogus in ["", "not hex at all", String(real.dropLast(2)), String(real.dropFirst()),
                      real + "00", "zz" + String(real.dropFirst(2))] {
            XCTAssertEqual(judge(rules, mac: bogus, key: established()),
                           .broken, "accepted a seal of \(bogus.count) characters")
        }
    }

    // MARK: - The upgrade

    /// Trust on first use. Somebody who has been using Autopilot has rules and
    /// no MAC, and refusing them would destroy real configuration — a worse
    /// defect than the one the seal exists to close.
    func testRulesWithNoSealAreAdoptedOnTheRunThatCreatedTheKey() {
        XCTAssertEqual(judge(payload(), mac: nil, key: fresh()), .adopt)
        XCTAssertEqual(judge(payload(), mac: "", key: fresh()), .adopt)
    }

    /// And the weakness of trust on first use, closed as far as it can be: once
    /// the key exists, an unsealed rule set is not a rule set from before the
    /// seal — it is a rule set somebody wrote without one. Without this, the
    /// attack is to delete `foldersMAC` along with writing the rules, and every
    /// run is a first run.
    func testRulesWithNoSealAreRefusedOnceTheKeyExists() {
        XCTAssertEqual(judge(payload(), mac: nil, key: established()), .broken)
        XCTAssertEqual(judge(payload(), mac: "", key: established()), .broken)
    }

    /// A MAC written by somebody who did not have the key is not a migration
    /// either, whatever state the key is in.
    func testAForgedSealIsNotMistakenForAMigration() {
        let verdict = judge(payload(), mac: RuleSeal.mac(for: payload(), seq: 0, key: other),
                            key: fresh())

        XCTAssertEqual(verdict, .broken)
    }

    // MARK: - The rule set before this one

    /// **A seal proves who wrote a rule set and not when.** The plist is
    /// readable by anything running as the user and sits in every backup, so
    /// keeping a copy of a `(payload, MAC)` pair costs nothing — and putting it
    /// back is not tampering: the pair verifies, because Helm really did write
    /// it. The rule the person deleted this morning runs again tonight.
    ///
    /// So the number that says *which* rule set it is goes inside the sealed
    /// message, and the highest number this Mac has ever sealed is kept where
    /// the plist's author cannot reach it.
    func testARuleSetOlderThanTheOneThisMacLastSealedIsRefused() {
        let old = payload("the rule the person deleted")
        let mac = RuleSeal.mac(for: old, seq: 4, key: material)

        XCTAssertEqual(judge(old, mac: mac, key: established(), seq: 4, highWater: 4), .sealed,
                       "the premise: this pair is Helm's own and verifies")
        XCTAssertEqual(judge(old, mac: mac, key: established(), seq: 4, highWater: 5), .rolledBack)
    }

    /// And the number cannot be raised on its own, because it is inside the
    /// message: editing it in the plist to clear the mark breaks the seal.
    func testTheNumberCannotBeEditedWithoutBreakingTheSeal() {
        let old = payload("the rule the person deleted")
        let mac = RuleSeal.mac(for: old, seq: 4, key: material)

        XCTAssertEqual(judge(old, mac: mac, key: established(), seq: 9, highWater: 5), .broken)
    }

    /// The number is part of the message, so two rule sets that differ only by
    /// it do not share a seal — the property the line above rests on, stated
    /// where it cannot be satisfied by accident.
    func testTheSealDependsOnTheNumber() {
        XCTAssertNotEqual(RuleSeal.mac(for: payload(), seq: 4, key: material),
                          RuleSeal.mac(for: payload(), seq: 5, key: material))
    }

    /// A rule set at the mark is the current one, not an old one: saving does
    /// not have to raise the mark twice to be believed.
    func testTheRuleSetAtTheMarkIsTheCurrentOne() {
        let now = payload()
        let mac = RuleSeal.mac(for: now, seq: 7, key: material)

        XCTAssertEqual(judge(now, mac: mac, key: established(), seq: 7, highWater: 7), .sealed)
    }

    /// **The upgrade, again.** Every Mac that has run Autopilot has a sealed
    /// rule set with no number beside it and no mark to compare against, and a
    /// build that refused those would be a build that throws away the rules of
    /// everyone who installs it. A message with no number is the payload alone,
    /// byte for byte what the old build signed.
    func testARuleSetSealedBeforeThereWereNumbersIsStillRun() {
        let rules = payload()
        let old = SettingSeal.mac(for: rules, key: material)

        XCTAssertEqual(judge(rules, mac: old, key: established()), .sealed)
        XCTAssertEqual(judge(rules, mac: old, key: established(), seq: 0, highWater: nil), .sealed)
    }

    /// The number a save takes is above both the plist's and the mark's.
    ///
    /// Above the plist's, because that is what makes it count saves. Above the
    /// mark's, because a keychain that would not answer at the moment of a save
    /// must not be able to hand out a number an earlier rule set already has —
    /// which would make the rule set that is current look like a rolled-back one
    /// for ever after.
    func testTheNextNumberIsAboveBothWhatIsStoredAndTheMark() {
        XCTAssertEqual(RuleSeal.next(after: 0, mark: .absent), 1)
        XCTAssertEqual(RuleSeal.next(after: 3, mark: .absent), 4)
        XCTAssertEqual(RuleSeal.next(after: 3, mark: .unavailable), 4)
        XCTAssertEqual(RuleSeal.next(after: 3, mark: .at(9)), 10, "the mark was ignored")
        XCTAssertEqual(RuleSeal.next(after: 9, mark: .at(3)), 10, "the plist was ignored")
    }

    /// But not once this Mac has sealed a numbered one: a payload with no number
    /// arriving after the mark exists is the oldest rollback there is.
    func testARuleSetWithNoNumberIsRefusedOnceThisMacHasSealedOne() {
        let rules = payload()
        let old = SettingSeal.mac(for: rules, key: material)

        XCTAssertEqual(judge(rules, mac: old, key: established(), seq: 0, highWater: 1),
                       .rolledBack)
    }
}
