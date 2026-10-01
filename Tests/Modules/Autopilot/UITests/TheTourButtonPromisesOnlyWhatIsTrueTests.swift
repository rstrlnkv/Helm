import HelmContract
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Autopilot_UI

/// The tour's button on Autopilot's step promised «the rules to start with» to
/// everybody, and the block of starting rules is on the page only while there
/// are no rules at all. A person who has rules — the tour shown once to an
/// existing install, or reopened — pressed it and found no such thing.
///
/// The descriptor's metadata is static and the tour holds no reading of the
/// rules, so the button cannot be hidden from here; it says what is always true
/// instead, and the page's own menu keeps the old words, where they are.
@MainActor
final class TheTourButtonPromisesOnlyWhatIsTrueTests: XCTestCase {

    func testTheTourOffersToOpenTheModuleInEveryLanguage() {
        AppLanguage.each { language in
            let offer = AutopilotDescriptor.metadata.welcomeOffer
            XCTAssertEqual(offer, L("Open Autopilot", language: language), "\(language)")
            XCTAssertNotEqual(offer, L("Show the rules to start with", language: language),
                              "\(language): the tour promises the starting rules again")
        }
    }

    func testTheWordsAreTranslatedAndNameTheModule() {
        AppLanguage.each { language in
            let offer = L("Open Autopilot", language: language)
            if language != .en {
                XCTAssertNotEqual(offer, "Open Autopilot", "\(language) fell back to English")
            }
            let module = L("Autopilot", language: language)
            XCTAssertTrue(offer.contains(module), "\(language): «\(offer)» does not name «\(module)»")
        }
    }

    /// The page's own menu is unchanged: it is drawn only where there are no
    /// rules, so its words are true there.
    func testThePageMenuKeepsItsWords() {
        AppLanguage.only(.en) {
            XCTAssertEqual(ApStr.welcomeOffer, "Show the rules to start with")
        }
    }
}
