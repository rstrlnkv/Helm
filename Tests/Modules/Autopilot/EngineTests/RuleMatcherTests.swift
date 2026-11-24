import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// The facts and rule builders both matcher classes below stand on.
class RuleMatcherRig: XCTestCase {

    fileprivate func facts(name: String = "invoice.pdf",
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

    fileprivate func rule(_ match: RuleMatch, _ conditions: [RuleCondition]) -> Rule {
        Rule(id: "r", name: "test", enabled: true, match: match,
             conditions: conditions, action: .trash)
    }
}

/// Whether a file matches a rule. Everything here is arithmetic on facts — no
/// filesystem — which is the point of `FileFacts` existing at all: the question
/// "would this rule fire" has to be answerable without a file to fire it on.
final class RuleMatcherTests: RuleMatcherRig {

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
