import Foundation
import XCTest
@testable import Module_Layout_Engine

/// The order `LanguageBadge.region` searches its table in.
///
/// It scanned with `byLayout.first(where:)`, and a `Dictionary` is walked in an
/// order that comes from a hash seeded per process. So a layout name two keys
/// both prefix resolved to whichever the seed put first, and the flag in the
/// menu bar could differ between launches with no code change — the same defect
/// `Duplicates.refine` documents and avoids by sorting.
///
/// `BadgeTableAmbiguityTests` constrains the table so that no such pair
/// disagrees about the country. That is a useful rule and it is not a fix: it
/// asks every future entry to be checked by hand against every existing one,
/// and the table already has `Canadian` and `Canadian-CSA` in it.
///
/// These are about the scan instead. The property has to be stated over the
/// order rather than over one call, because with today's entries there is no
/// input whose answer differs — which is exactly what makes an assertion on
/// answers worth nothing here.
///
/// That the order has not *lost* an entry is asserted next to the table
/// parser, in `BadgeTableAmbiguityTests`, so `byLayout` can stay private —
/// nothing outside `LanguageBadge` may scan it, which is how the hash order got
/// in.
final class BadgeSearchOrderTests: XCTestCase {

    /// The rule, as an assertion: a key that another key starts with is never
    /// reached first. Longest-first gives this, and so would anything else that
    /// prefers the more specific claim; what must not survive is a scan whose
    /// order the process decides.
    func testNoKeyIsReachedBeforeALongerKeyItStarts() {
        let ordered = LanguageBadge.ordered
        var wrong: [String] = []
        for (index, entry) in ordered.enumerated() {
            for later in ordered[ordered.index(after: index)...]
            where later.key.hasPrefix(entry.key) {
                wrong.append("\(entry.key) is searched before \(later.key), which it starts")
            }
        }
        XCTAssertEqual(wrong, [], wrong.joined(separator: "\n"))
    }

    /// Sorting on length alone leaves keys of equal length in whatever order
    /// the dictionary handed them over, which is the defect again one level
    /// down. The tie-break is the key itself.
    func testKeysOfTheSameLengthAreStillInAFixedOrder() {
        let ordered = LanguageBadge.ordered
        for (index, entry) in ordered.enumerated()
        where index + 1 < ordered.count && ordered[index + 1].key.count == entry.key.count {
            XCTAssertGreaterThan(entry.key, ordered[index + 1].key,
                                 "\(entry.key) and \(ordered[index + 1].key) are the same "
                                 + "length and the order between them is the seed's")
        }
    }

    /// The pair that exists today, through the public answer. Both say CA, so
    /// this cannot catch the defect — it is here so that a future entry which
    /// makes the pair disagree is caught by a name somebody recognises rather
    /// than only by the order test above.
    func testTheMoreSpecificCanadianLayoutAnswers() {
        XCTAssertEqual(LanguageBadge.ordered.first { "Canadian-CSA".hasPrefix($0.key) }?.key,
                       "Canadian-CSA")
        XCTAssertEqual(LanguageBadge.region(sourceID: "com.apple.keylayout.Canadian-CSA",
                                            language: "fr"), "CA")
        XCTAssertEqual(LanguageBadge.region(sourceID: "com.apple.keylayout.Canadian",
                                            language: "en"), "CA")
    }
}
