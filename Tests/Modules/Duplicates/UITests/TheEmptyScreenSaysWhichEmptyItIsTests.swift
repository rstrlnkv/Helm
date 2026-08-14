import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The sentence over an empty result, and the page reaching for it.
///
/// `DuplicatesEmpty` decides *which* empty this is and has its own tests; what
/// those cannot see is whether the screen says anything different about the
/// three. It did not: one sentence — «No duplicates here. Every large file under
/// this folder is one of a kind» — was drawn whether the walk read the tree or
/// was refused at every door in it.
final class TheEmptyScreenSaysWhichEmptyItIsTests: XCTestCase {

    /// Every language, not `AppLanguage.current`: the suite runs in this Mac's
    /// language, so an assertion that reads `.current` exercises one of eight.
    func testEachReasonHasItsOwnSentenceInEveryLanguage() {
        for language in AppLanguage.allCases {
            let clean = DupStr.emptyMessage(.nothingFound, language: language)
            let refused = DupStr.emptyMessage(.notEverythingRead(3), language: language)
            let libraries = DupStr.emptyMessage(.librariesNotOpened(1), language: language)

            XCTAssertNotEqual(refused, clean, """
                a walk refused at every door is told it read a folder of one-of-a-kind files \
                (\(language.rawValue))
                """)
            XCTAssertNotEqual(libraries, clean,
                              "a library nobody opened is reported as read (\(language.rawValue))")
            XCTAssertNotEqual(refused, libraries, """
                a fault somebody can fix and a folder Helm declines to enter are one sentence \
                (\(language.rawValue))
                """)
        }
    }

    /// And the loop above is really eight languages. Two of the three sentences
    /// were `L(key)` with no language, which answers `AppLanguage.current` — so
    /// every pass of that loop compared the same Russian string against itself,
    /// and the one guard here that could see a collapsed sentence was reading one
    /// language eight times.
    func testTheLanguageAskedForIsTheLanguageAnswered() {
        for reason in Self.everyReason {
            XCTAssertNotEqual(DupStr.emptyMessage(reason, language: .en),
                              DupStr.emptyMessage(reason, language: .ru),
                              "\(reason) answers one language whatever it is asked")
        }
    }

    /// Named once, so a fourth reason joins these checks by being added to the
    /// enum rather than by somebody remembering this file.
    private static let everyReason: [DuplicatesEmpty.Reason] =
        [.nothingFound, .notEverythingRead(3), .librariesNotOpened(1)]

    /// And the count is in it, or the sentence is a shrug: «some of it» is not
    /// something anybody can act on.
    func testTheRefusalSaysHowMuchItCouldNotRead() {
        for language in AppLanguage.allCases {
            let one = DupStr.emptyMessage(.notEverythingRead(1), language: language)
            let many = DupStr.emptyMessage(.notEverythingRead(12), language: language)
            XCTAssertNotEqual(one, many,
                              "the same sentence for 1 and for 12 (\(language.rawValue))")
            XCTAssertTrue(many.contains("12"),
                          "the count never reached the sentence: \(many) (\(language.rawValue))")
        }
    }

    /// And a search still running says nothing about the one before it.
    ///
    /// `search()` empties `groups` on its first line and the counts arrive with
    /// the reply, so without the reset beside it the model spends the whole walk
    /// answering «Helm could not read 1 item» about a folder nobody is reading
    /// any more. The reset looked redundant with the assignment on the reply and
    /// was measured not to be: this is the window where the two differ, and a
    /// transport that answers on the spot is past it before anything can ask.
    @MainActor
    func testASearchInFlightMakesNoClaimAboutTheWalkBeforeIt() async {
        let wire = DuplicatesWire(groups: [], unreadable: 4)
        let dvm = await searchedModel(over: wire)
        XCTAssertEqual(dvm.nothingToShow, .notEverythingRead(4),
                       "precondition: the first walk really was refused")

        wire.answers(.park, to: .find)
        dvm.search()
        for _ in 0..<1000 where wire.parkedCount < 1 { await Task.yield() }

        XCTAssertEqual(wire.parkedCount, 1, "precondition: the second search is in flight")
        XCTAssertEqual(dvm.unreadable, 0, """
            the previous walk's refusal is still on the model while a new walk is running, so a \
            sentence about a folder nobody is reading any more is one redraw from its list
            """)
        XCTAssertNotEqual(dvm.nothingToShow, .notEverythingRead(4),
                          "and the rule reads it, so the claim survives with it")
        wire.releaseParked()
        for _ in 0..<200 where dvm.phase == .searching { await Task.yield() }
    }

    /// The page's half. The strings can all differ and still never be drawn: the
    /// branch used to be `groups.isEmpty`, which is the same question with only
    /// one answer.
    ///
    /// Read from source rather than rendered, as this target's other page checks
    /// are — a test that needs a window server is green here and absent on the
    /// next machine.
    func testThePageAsksWhichEmptyItIsRatherThanWhetherItIsEmpty() throws {
        let lines = try RepoSource
            .lines(of: "Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift")
        let empty = try XCTUnwrap(lines.firstIndex { $0.contains("HelmEmptyState(message:") },
                                  "the result screen no longer draws that component")
        XCTAssertTrue(lines[empty].contains("DupStr.emptyMessage"), """
            the empty result draws one fixed sentence, so «No duplicates here» stands over a \
            tree nobody could read: \(lines[empty])
            """)
        XCTAssertTrue(lines[(empty - 2)..<empty].joined().contains("dvm.nothingToShow"), """
            the page still branches on whether the list is empty rather than on why: \
            \(lines[(empty - 2)..<empty].joined(separator: "\n"))
            """)
    }
}
