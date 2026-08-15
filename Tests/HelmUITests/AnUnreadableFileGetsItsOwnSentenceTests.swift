import HelmRuntime
import XCTest
@testable import HelmUI

/// A file the removal could not read is not a file that moved.
///
/// The verification's `.unreadable` verdict was folded into `changedSinceScan`,
/// so the person read «This is not where Helm found it» about a file that was
/// exactly where Helm found it — a permission withdrawn, a volume gone, or the
/// *surviving* copy unreadable. The two facts are acted on differently: a
/// person told «it moved» looks for the file; a person told «it could not be
/// read» checks the access.
final class AnUnreadableFileGetsItsOwnSentenceTests: XCTestCase {

    /// Parameterized by language rather than gated on `AppLanguage.current`,
    /// which on this Mac is `.ru`.
    func testEveryLanguageTellsUnreadableApartFromMovedAndRefused() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let unreadable = TrashReasonText.sentence(TrashFailure.Reason.unreadable.rawValue)
            let changed = TrashReasonText.sentence(TrashFailure.Reason.changedSinceScan.rawValue)
            let refused = TrashReasonText.sentence(TrashFailure.Reason.systemRefused.rawValue)

            XCTAssertFalse(unreadable.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(language.rawValue) has nothing to say about a file it could not read")
            XCTAssertNotEqual(unreadable, changed, """
                \(language.rawValue) tells a file it could not read that it moved — the fold \
                this case exists to undo.
                """)
            XCTAssertNotEqual(unreadable, refused, """
                \(language.rawValue) answers a read failure with the general refusal, which \
                sends somebody to the Finder instead of to the access.
                """)
        }
    }
}
