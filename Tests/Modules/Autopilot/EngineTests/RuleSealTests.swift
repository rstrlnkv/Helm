import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// The seal that binds a rule set to this installation.
///
/// Autopilot's rules are JSON in a plist any process running as the user can
/// write, and the module runs them unattended on an hourly timer with Helm's
/// Full Disk Access behind it. Everything else in the module — `WatchScope`,
/// the stamp, the dry run — assumes the rules came from the person. This is
/// the type that decides whether that assumption holds.
///
/// The assertions here are about the verdict, never about the bytes of a MAC:
/// a test that pinned a hex string would pass just as happily with a broken
/// comparison behind it.
final class RuleSealTests: XCTestCase {

    private let material = Data(repeating: 0x5A, count: 32)
    private let other = Data(repeating: 0xA5, count: 32)

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
        let mac = RuleSeal.mac(for: rules, key: material)

        XCTAssertEqual(RuleSeal.verdict(payload: rules, mac: mac, key: established()), .sealed)
    }

    /// And the seal has to be spent by the key, not by the payload: a MAC any
    /// process could recompute from the rules alone secures nothing.
    func testTheSealDependsOnTheKey() {
        let rules = payload()

        XCTAssertNotEqual(RuleSeal.mac(for: rules, key: material),
                          RuleSeal.mac(for: rules, key: other))
        XCTAssertEqual(RuleSeal.verdict(payload: rules,
                                        mac: RuleSeal.mac(for: rules, key: other),
                                        key: established()),
                       .broken)
    }

    // MARK: - Tampering

    /// The reviewer's attack, reduced: the rules are rewritten in the plist and
    /// the MAC beside them is left as it was.
    func testRulesEditedAfterSealingAreRefused() {
        let mac = RuleSeal.mac(for: payload(), key: material)

        let verdict = RuleSeal.verdict(payload: payload("move everything out of the vault"),
                                       mac: mac, key: established())

        XCTAssertEqual(verdict, .broken)
    }

    /// A MAC that is not a MAC — truncated, non-hex, odd-length — is a refusal
    /// and never a crash or an accident.
    func testASealThatIsNotOneIsRefused() {
        let rules = payload()
        let real = RuleSeal.mac(for: rules, key: material)
        for bogus in ["", "not hex at all", String(real.dropLast(2)), String(real.dropFirst()),
                      real + "00", "zz" + String(real.dropFirst(2))] {
            XCTAssertEqual(RuleSeal.verdict(payload: rules, mac: bogus, key: established()),
                           .broken, "accepted a seal of \(bogus.count) characters")
        }
    }

    // MARK: - The upgrade

    /// Trust on first use. Somebody who has been using Autopilot has rules and
    /// no MAC, and refusing them would destroy real configuration — a worse
    /// defect than the one the seal exists to close.
    func testRulesWithNoSealAreAdoptedOnTheRunThatCreatedTheKey() {
        XCTAssertEqual(RuleSeal.verdict(payload: payload(), mac: nil, key: fresh()), .adopt)
        XCTAssertEqual(RuleSeal.verdict(payload: payload(), mac: "", key: fresh()), .adopt)
    }

    /// And the weakness of trust on first use, closed as far as it can be: once
    /// the key exists, an unsealed rule set is not a rule set from before the
    /// seal — it is a rule set somebody wrote without one. Without this, the
    /// attack is to delete `foldersMAC` along with writing the rules, and every
    /// run is a first run.
    func testRulesWithNoSealAreRefusedOnceTheKeyExists() {
        XCTAssertEqual(RuleSeal.verdict(payload: payload(), mac: nil, key: established()), .broken)
        XCTAssertEqual(RuleSeal.verdict(payload: payload(), mac: "", key: established()), .broken)
    }

    /// A MAC written by somebody who did not have the key is not a migration
    /// either, whatever state the key is in.
    func testAForgedSealIsNotMistakenForAMigration() {
        let verdict = RuleSeal.verdict(payload: payload(),
                                       mac: RuleSeal.mac(for: payload(), key: other),
                                       key: fresh())

        XCTAssertEqual(verdict, .broken)
    }
}
