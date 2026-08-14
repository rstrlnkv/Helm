import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **«refused changedSinceCheck» is what a refusal used to say — in all eight
/// languages.** The history row glued the localized verb to the reason's
/// rawValue, so the one line whose whole purpose is "tell the person why their
/// file was left alone" answered with an identifier out of the source code.
final class ARefusalSpeaksTheLanguageTests: XCTestCase {

    private let rule = Rule(id: "r", name: "Sort downloads", enabled: true,
                            action: .move(to: "/Users/x/Documents"))

    private func plan(_ path: String) -> RulePlan {
        let at = Date(timeIntervalSince1970: 0)
        return RulePlan(facts: FileFacts(name: (path as NSString).lastPathComponent,
                                         path: path, kind: .document, bytes: 1,
                                         added: at, modified: at, now: at),
                        rule: rule)
    }

    /// The record stores the reason's rawValue — data, stable across releases —
    /// and the page reads it back into the enum before it speaks. Asserted
    /// first, so the language assertions below are about records that really
    /// carry a reason: a renamed case would leave old records with a detail no
    /// reason claims, and this is the test that says so.
    func testAStoredRefusalRoundTripsToItsReason() throws {
        for reason in RuleOutcome.Refusal.allCases {
            let record = try XCTUnwrap(ActionRecord.of(plan("/Users/x/Downloads/a.pdf"),
                                                       .refused(reason),
                                                       at: Date(timeIntervalSince1970: 1)))
            XCTAssertEqual(RuleOutcome.Refusal(rawValue: record.detail), reason,
                           "the detail the record stores no longer names its reason")
        }
    }

    /// Every reason, every language: a sentence, not an identifier, and four
    /// reasons stay four different sentences. The rawValue is glued in verbatim
    /// by the defect this pins, so `contains` catches it in Russian as surely
    /// as in English.
    func testEveryReasonReadsAsASentenceInEveryLanguage() {
        for language in AppLanguage.allCases {
            var lines = Set<String>()
            for reason in RuleOutcome.Refusal.allCases {
                let line = ApStr.historyRefusal(reason, language: language)
                XCTAssertFalse(line.isEmpty,
                               "\(language.rawValue) says nothing for \(reason.rawValue)")
                XCTAssertFalse(line.contains(reason.rawValue),
                               "\(language.rawValue) shows the enum's rawValue for \(reason.rawValue): \(line)")
                lines.insert(line)
            }
            XCTAssertEqual(lines.count, RuleOutcome.Refusal.allCases.count,
                           "\(language.rawValue): two reasons collapsed onto one sentence")
        }
    }
}
