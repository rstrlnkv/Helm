import HelmRuntime
import HelmTestSupport
@testable import HelmUI
import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **A rule line and a history detail are one catalog key each (decision 17),
/// and "Put back 1 file" is singular.** Held for the class a fragment-built
/// sentence belongs to: a value dropped by a key, a key shared by two shapes,
/// a detail silently lost in a language.
@MainActor
final class RuleAndHistoryLinesAreWholeKeysTests: XCTestCase {

    private let value = "ZQX7"

    private func rule(_ condition: RuleCondition, _ action: RuleAction = .trash) -> String {
        RuleSummary.describe(Rule(name: "r", conditions: [condition], action: action))
    }

    private var conditions: [RuleCondition] {
        var all: [RuleCondition] = []
        for c in TextComparison.allCases {
            all.append(.name(c, value))
            all.append(.baseName(c, value))
        }
        all.append(.fileExtension([value]))
        all.append(.kind(.image))
        all.append(.size(.largerThan, megabytes: 7)); all.append(.size(.smallerThan, megabytes: 7))
        all.append(.dateAdded(.olderThan, days: 7)); all.append(.dateAdded(.newerThan, days: 7))
        all.append(.dateModified(.olderThan, days: 7)); all.append(.dateModified(.newerThan, days: 7))
        all.append(.downloadedFrom(value))
        all.append(.tag(value))
        return all
    }

    /// Asserted first: the subject speaks at all, so "distinct" below is not eight empties.
    func testEveryShapeSaysItsValueInEveryLanguage() {
        AppLanguage.each { language in
            for c in conditions {
                let line = self.rule(c)
                let needle = line.contains(self.value) || line.contains("7") || line.contains(ApStr.kindName(.image))
                XCTAssertTrue(needle, "\(language) \(c): \(line)")
                XCTAssertFalse(line.contains("%@") || line.contains("%lld"), "\(language) \(c): \(line)")
            }
        }
    }

    func testNoTwoShapesShareASentence() {
        AppLanguage.each { language in
            let lines = self.conditions.map { self.rule($0) }
            XCTAssertEqual(Set(lines).count, lines.count, "\(language): \(lines)")
        }
    }

    func testEveryActionSaysItsArgument() {
        AppLanguage.each { language in
            let actions: [RuleAction] = [.move(to: "/tmp/" + self.value), .rename(pattern: self.value),
                                         .addTag(self.value)]
            for a in actions {
                let line = RuleSummary.describe(a)
                XCTAssertTrue(line.contains(self.value), "\(language) \(a): \(line)")
            }
            let sorts = [RuleSummary.describe(.sortIntoSubfolder(.kind)),
                         RuleSummary.describe(.sortIntoSubfolder(.month)),
                         RuleSummary.describe(.trash)]
            XCTAssertEqual(Set(sorts).count, 3, "\(language)")
            XCTAssertFalse(sorts.contains(""), "\(language)")
        }
    }

    private func record(_ kind: ActionRecord.Kind, _ detail: String) -> ActionRecord {
        ActionRecord(at: Date(), rule: "r", file: "a.pdf", kind: kind, detail: detail)
    }

    func testHistoryDetailKeepsTheDetailInEveryLanguage() {
        AppLanguage.each { language in
            for kind: ActionRecord.Kind in [.moved, .renamed, .tagged, .failed, .refused] {
                // An unknown refusal reason (a newer Helm's) keeps its value.
                let line = ApStr.historyDetail(self.record(kind, self.value))
                XCTAssertTrue(line.contains(self.value), "\(language) \(kind): \(line)")
                XCTAssertFalse(line.contains("%@"), "\(language) \(kind): \(line)")
            }
            let trashed = ApStr.historyDetail(self.record(.trashed, "ignored"))
            XCTAssertFalse(trashed.isEmpty, "\(language)")
            XCTAssertFalse(trashed.contains("ignored"), "\(language)")
            XCTAssertEqual(ApStr.historyDetail(self.record(.moved, "")), ApStr.historyVerb(.moved), "\(language)")
        }
    }

    func testAKnownRefusalIsSpokenNotPrinted() {
        AppLanguage.each { language in
            for reason in RuleOutcome.Refusal.allCases {
                let line = ApStr.historyDetail(self.record(.refused, reason.rawValue))
                XCTAssertEqual(line, ApStr.historyRefusal(reason), "\(language)")
                XCTAssertFalse(line.contains(reason.rawValue), "\(language) \(reason): \(line)")
            }
        }
    }

    func testPutBackOneFileIsSingular() {
        XCTAssertEqual(ApStr.putBackFiles(1, language: .en), "Put back 1 file")
        XCTAssertEqual(ApStr.putBackFiles(5, language: .en), "Put back 5 files")
        for language in AppLanguage.allCases {
            let one = ApStr.putBackFiles(1, language: language)
            let five = ApStr.putBackFiles(5, language: language)
            XCTAssertTrue(one.contains("1"), "\(language): \(one)")
            XCTAssertTrue(five.contains("5"), "\(language): \(five)")
            // Japanese and Chinese have no grammatical number.
            if language == .ja || language == .zh { continue }
            XCTAssertNotEqual(one.replacingOccurrences(of: "1", with: "#"),
                              five.replacingOccurrences(of: "5", with: "#"),
                              "\(language) counts the noun the same at 1 and 5")
        }
    }
}
