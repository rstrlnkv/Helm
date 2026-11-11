import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Duplicates_UI

/// The words Duplicates took from the kit's basket strings and from its own
/// catalog, read in each language.
///
/// A row's checkbox is read out once per row, so its label must carry the file's
/// name, say the opposite of its twin, and be a sentence in the language rather
/// than the English text or a catalog symbol. The start screen with a folder
/// already chosen has a sentence of its own, which must differ from the one that
/// asks for a folder.
@MainActor
final class TheKitsRowWordsAndTheFolderHintReachEveryLanguageTests: XCTestCase {

    private let file = "Report 2024.pdf"

    func testTheRowLabelNamesTheFileAndMarkIsNotUnmark() {
        let english = HelmBasket.mark(name: file, language: .en)
        AppLanguage.each { language in
            let mark = HelmBasket.mark(name: file, language: language)
            let unmark = HelmBasket.unmark(name: file, language: language)
            XCTAssertTrue(mark.contains(file), "\(language): mark lost the file name: \(mark)")
            XCTAssertTrue(unmark.contains(file), "\(language): unmark lost the file name: \(unmark)")
            XCTAssertNotEqual(mark, unmark, "\(language): mark and unmark read alike")
            if language != .en {
                XCTAssertNotEqual(mark, english, "\(language): mark is still the English text")
            }
        }
    }

    func testTheTrashSentenceCarriesTheSizeInEveryLanguage() {
        AppLanguage.each { language in
            let line = HelmBasket.movedToTrash("12 MB", language: language)
            XCTAssertTrue(line.contains("12 MB"), "\(language): \(line)")
            if language != .en {
                XCTAssertNotEqual(line, HelmBasket.movedToTrash("12 MB", language: .en), "\(language)")
            }
            XCTAssertEqual(DupStr.movedToTrash("12 MB"), line, "\(language): Duplicates says it differently")
        }
    }

    func testTheHintWithAFolderIsASentenceOfItsOwn() {
        var english = ""
        AppLanguage.only(.en) { english = DupStr.startHintWithFolder }
        AppLanguage.each { language in
            let with = DupStr.startHintWithFolder
            let without = DupStr.startHint
            XCTAssertFalse(with.isEmpty, "\(language)")
            XCTAssertNotEqual(with, without, "\(language): the hint asks for a folder that is chosen")
            XCTAssertFalse(with.contains("helmWillReadThisFolder"), "\(language): a symbol on screen")
            if language != .en {
                XCTAssertNotEqual(with, english, "\(language): still English")
            }
        }
    }
}
