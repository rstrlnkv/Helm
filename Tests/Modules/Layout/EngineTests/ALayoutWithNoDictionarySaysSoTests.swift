import XCTest
@testable import Module_Layout_Engine

/// macOS ships spelling for 44 languages, and the list is not the one anybody
/// assumes: measured on this Mac, `NSSpellChecker.availableLanguages` has no
/// Kazakh, Belarusian, Georgian, Armenian, Serbian, Thai, Japanese or Chinese.
///
/// `SpellPort.isWord` answers `nil` for those — «no dictionary», which is not
/// «not a word» — and the engine returns outright when either side is nil. So
/// on such a layout «Fix as I type» is dead, and the page says nothing at all:
/// the switch is on, the badge is green, and no word is ever fixed.
///
/// The gesture is a different matter and keeps working — `decideForced` asks no
/// dictionary — so the sentence the page owes is not «this module cannot work»
/// but «it cannot decide for itself here; ask it and it will».
final class ALayoutWithNoDictionarySaysSoTests: XCTestCase {

    private let ru = "com.apple.keylayout.Russian"
    private let us = "com.apple.keylayout.US"
    private let kk = "com.apple.keylayout.Kazakh"
    private let ka = "com.apple.keylayout.Georgian"

    func testEveryLayoutHavingADictionaryIsSilence() {
        XCTAssertEqual(DictionarySupport.missing(installed: [ru, us]) { _ in true }, [])
    }

    func testTheLayoutsWithoutOneAreNamedInTheOrderTheyAreInstalled() {
        let missing = DictionarySupport.missing(installed: [ru, kk, us, ka]) { id in
            id == self.ru || id == self.us
        }
        XCTAssertEqual(missing, [kk, ka])
    }

    /// **The whole list, not the current one.** A conversion needs a verdict on
    /// both sides — the word as typed and the word translated — so a missing
    /// dictionary anywhere in the installed set is a hole in the pairs that
    /// include it, whichever one happens to be active right now.
    func testALayoutIsNamedEvenWhenItIsNotTheActiveOne() {
        XCTAssertEqual(DictionarySupport.missing(installed: [ru, us, kk]) { $0 != self.kk }, [kk])
    }

    /// One layout installed is not a working configuration for this module at
    /// all, and that is a different sentence — there is nothing to convert
    /// into. It is not this type's to say.
    func testASingleLayoutIsNotThisTypesProblem() {
        XCTAssertEqual(DictionarySupport.missing(installed: [kk]) { _ in false }, [kk])
    }

    /// The probe is asked once per layout, not once per word: the real one costs
    /// about 150 µs and this runs where the page is drawn.
    func testEachLayoutIsAskedOnce() {
        var asked: [String] = []
        _ = DictionarySupport.missing(installed: [ru, us, kk]) { id in asked.append(id); return true }
        XCTAssertEqual(asked, [ru, us, kk])
    }
}
