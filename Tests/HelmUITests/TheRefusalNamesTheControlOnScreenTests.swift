import HelmRuntime
import XCTest
@testable import HelmUI

/// The two refusal sentences that end by naming a control take that control's
/// verb from the caller.
///
/// «Scan again to see where it is now» was said on four screens, and one of
/// them — Duplicates — has no such button: its control says «Search again».
/// A record that names a control is checked against the app's real string
/// (CLAUDE.md § A changelog entry that names a control), so the sentence comes
/// in the caller's own verb: three modules keep `.scan`, Duplicates asks for
/// `.search`, and each is a full key with its own eight translations rather
/// than a verb interpolated into somebody's grammar.
final class TheRefusalNamesTheControlOnScreenTests: XCTestCase {

    /// Parameterized by language rather than gated on `AppLanguage.current`,
    /// which on this Mac is `.ru`.
    func testEveryLanguageHasASearchVariantOfBothSentences() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in AppLanguage.allCases {
            AppLanguage.override = language
            for raw in [TrashFailure.Reason.changedSinceScan.rawValue,
                        TrashFailure.Reason.missing.rawValue] {
                let scan = TrashReasonText.sentence(raw)
                let search = TrashReasonText.sentence(raw, refresh: .search)
                XCTAssertFalse(search.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(language.rawValue): \(raw) has no search-worded sentence")
                XCTAssertNotEqual(search, scan, """
                    \(language.rawValue): the \(raw) sentence reads the same whichever \
                    control the page has, so one of the two screens names a button \
                    it does not have.
                    """)
            }
        }
    }

    /// The verb is the only difference asked for: a refusal that does not end
    /// by naming a control says the same thing to both callers.
    func testSentencesThatNameNoControlIgnoreTheVerb() {
        for raw in [TrashFailure.Reason.outOfScope.rawValue,
                    TrashFailure.Reason.noPermission.rawValue,
                    TrashFailure.Reason.systemRefused.rawValue] {
            XCTAssertEqual(TrashReasonText.sentence(raw),
                           TrashReasonText.sentence(raw, refresh: .search),
                           "\(raw) names no control, so the verb changes nothing in it")
        }
    }

    /// And the failure row built from a refusal carries the caller's verb — the
    /// page maps refusals through `HelmRemovalFailure`, so a verb the sentence
    /// takes and the row never asks for would fix nothing on screen.
    func testAFailureRowCarriesTheCallersVerb() {
        let refusal = HelmTrash.Refusal(path: "/Users/me/a.bin", reason: .changedSinceScan)
        XCTAssertEqual(HelmRemovalFailure(refusal, refresh: .search).reason,
                       TrashReasonText.sentence(refusal.reason.rawValue, refresh: .search))
        XCTAssertEqual(HelmRemovalFailure(refusal).reason,
                       TrashReasonText.sentence(refusal.reason.rawValue),
                       "the default stays `.scan`, so the three scan modules are untouched")
    }
}
