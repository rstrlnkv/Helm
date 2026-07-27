import Foundation
import XCTest
@testable import Module_Rules_Engine

/// Whether a file matches a rule. Everything here is arithmetic on facts — no
/// filesystem — which is the point of `FileFacts` existing at all: the question
/// "would this rule fire" has to be answerable without a file to fire it on.
final class RuleMatcherTests: XCTestCase {

    private func facts(name: String = "invoice.pdf",
                       kind: FileKind = .document,
                       bytes: Int = 2_000_000,
                       addedDaysAgo: Double = 1,
                       modifiedDaysAgo: Double = 1,
                       from: String? = nil,
                       tags: [String] = [],
                       isDirectory: Bool = false) -> FileFacts {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return FileFacts(name: name,
                         kind: kind,
                         bytes: bytes,
                         added: now.addingTimeInterval(-addedDaysAgo * 86_400),
                         modified: now.addingTimeInterval(-modifiedDaysAgo * 86_400),
                         downloadedFrom: from,
                         tags: tags,
                         isDirectory: isDirectory,
                         now: now)
    }

    /// Two helpers rather than one with a defaulted first parameter: with both
    /// positions unlabelled, `rule([...])` is ambiguous often enough that the
    /// failures read as errors in the conditions rather than in the call.
    private func rule(_ conditions: [RuleCondition]) -> Rule {
        rule(.all, conditions)
    }

    private func rule(_ match: RuleMatch, _ conditions: [RuleCondition]) -> Rule {
        Rule(id: "r", name: "test", enabled: true, match: match,
             conditions: conditions, action: .trash)
    }

    // MARK: - Name

    func testNameComparisons() {
        let f = facts(name: "Invoice 2026.pdf")
        XCTAssertTrue(RuleMatcher.matches(f, rule([.name(.contains, "invoice")])))
        XCTAssertTrue(RuleMatcher.matches(f, rule([.name(.beginsWith, "inv")])))
        XCTAssertTrue(RuleMatcher.matches(f, rule([.name(.endsWith, "2026.pdf")])))
        XCTAssertTrue(RuleMatcher.matches(f, rule([.name(.is, "invoice 2026.pdf")])))
        XCTAssertFalse(RuleMatcher.matches(f, rule([.name(.contains, "receipt")])))
    }

    /// Case matters to a filesystem and not to a person writing a rule.
    func testNameIsCaseInsensitive() {
        let f = facts(name: "REPORT.PDF")
        XCTAssertTrue(RuleMatcher.matches(f, rule([.name(.contains, "report")])))
        XCTAssertTrue(RuleMatcher.matches(f, rule([.name(.is, "report.pdf")])))
    }

    // MARK: - Extension

    func testExtensionIsOneOf() {
        XCTAssertTrue(RuleMatcher.matches(facts(name: "a.png"),
                                          rule([.fileExtension(["pdf", "png"])])))
        XCTAssertFalse(RuleMatcher.matches(facts(name: "a.gif"),
                                           rule([.fileExtension(["pdf", "png"])])))
    }

    /// A file with no extension matches nothing rather than everything.
    func testAFileWithoutAnExtensionMatchesNoExtensionRule() {
        XCTAssertFalse(RuleMatcher.matches(facts(name: "Makefile"),
                                           rule([.fileExtension(["pdf"])])))
    }

    // MARK: - Size and dates

    func testSize() {
        let f = facts(bytes: 5_000_000)
        XCTAssertTrue(RuleMatcher.matches(f, rule([.size(.largerThan, megabytes: 4)])))
        XCTAssertFalse(RuleMatcher.matches(f, rule([.size(.largerThan, megabytes: 6)])))
        XCTAssertTrue(RuleMatcher.matches(f, rule([.size(.smallerThan, megabytes: 6)])))
    }

    func testDates() {
        let old = facts(addedDaysAgo: 40, modifiedDaysAgo: 40)
        XCTAssertTrue(RuleMatcher.matches(old, rule([.dateAdded(.olderThan, days: 30)])))
        XCTAssertFalse(RuleMatcher.matches(old, rule([.dateAdded(.newerThan, days: 30)])))
        XCTAssertTrue(RuleMatcher.matches(old, rule([.dateModified(.olderThan, days: 7)])))
    }

    /// The boundary a person means by "older than 30 days" is 30, not 29.999.
    func testTheDayBoundaryIsInclusiveOfTheOlderSide() {
        XCTAssertTrue(RuleMatcher.matches(facts(addedDaysAgo: 30),
                                          rule([.dateAdded(.olderThan, days: 30)])))
        XCTAssertFalse(RuleMatcher.matches(facts(addedDaysAgo: 29.9),
                                           rule([.dateAdded(.olderThan, days: 30)])))
    }

    // MARK: - Kind, source, tags

    func testKind() {
        XCTAssertTrue(RuleMatcher.matches(facts(kind: .image), rule([.kind(.image)])))
        XCTAssertFalse(RuleMatcher.matches(facts(kind: .image), rule([.kind(.archive)])))
    }

    /// The condition the module is worth having for: everything one site sent.
    func testDownloadedFrom() {
        let f = facts(from: "https://files.example.com/q3/report.pdf")
        XCTAssertTrue(RuleMatcher.matches(f, rule([.downloadedFrom("example.com")])))
        XCTAssertFalse(RuleMatcher.matches(f, rule([.downloadedFrom("other.com")])))
    }

    /// A file that arrived by any other route has no source, and a source
    /// condition must not quietly match it.
    func testAFileWithNoSourceNeverMatchesASourceCondition() {
        XCTAssertFalse(RuleMatcher.matches(facts(from: nil),
                                           rule([.downloadedFrom("example.com")])))
    }

    func testTag() {
        XCTAssertTrue(RuleMatcher.matches(facts(tags: ["Work", "Later"]),
                                          rule([.tag("work")])))
        XCTAssertFalse(RuleMatcher.matches(facts(tags: ["Later"]), rule([.tag("work")])))
    }

    // MARK: - all / any

    func testAllRequiresEveryCondition() {
        let f = facts(name: "invoice.pdf", bytes: 1_000_000)
        XCTAssertTrue(RuleMatcher.matches(f, rule(.all, [.name(.contains, "invoice"),
                                                         .size(.smallerThan, megabytes: 2)])))
        XCTAssertFalse(RuleMatcher.matches(f, rule(.all, [.name(.contains, "invoice"),
                                                          .size(.largerThan, megabytes: 2)])))
    }

    func testAnyRequiresOne() {
        let f = facts(name: "invoice.pdf", bytes: 1_000_000)
        XCTAssertTrue(RuleMatcher.matches(f, rule(.any, [.name(.contains, "receipt"),
                                                         .size(.smallerThan, megabytes: 2)])))
        XCTAssertFalse(RuleMatcher.matches(f, rule(.any, [.name(.contains, "receipt"),
                                                          .size(.largerThan, megabytes: 2)])))
    }

    /// A rule with nothing in it matches nothing. The other reading — that an
    /// empty `all` is vacuously true — would make a half-written rule act on
    /// every file in the folder, which is the worst thing this module can do.
    func testARuleWithNoConditionsMatchesNothing() {
        XCTAssertFalse(RuleMatcher.matches(facts(), rule(.all, [])))
        XCTAssertFalse(RuleMatcher.matches(facts(), rule(.any, [])))
    }

    /// Folders are files too, and a rule aimed at documents must not sweep the
    /// folder they were sorted into.
    func testADirectoryOnlyMatchesTheFolderKind() {
        let dir = facts(name: "Reports", kind: .folder, isDirectory: true)
        XCTAssertTrue(RuleMatcher.matches(dir, rule(.all, [.kind(.folder)])))
        XCTAssertFalse(RuleMatcher.matches(dir, rule(.all, [.kind(.document)])))
    }
}
