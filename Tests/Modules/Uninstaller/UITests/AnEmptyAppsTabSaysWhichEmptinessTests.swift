import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The Apps tab had no empty state at all.** `pickStep` branched on `loading`
/// alone, so a search matching nothing, a Mac whose folders really hold no
/// applications and a list the engine never answered all drew the same empty
/// inset `List` — under a footer that carefully says «Counting apps…» for the
/// third of them. The body was undoing the footer's honesty.
///
/// `AppsEmpty` holds the rule and `AppsEmptyTests` pins it; this is the half no
/// pure function can check — that the page asks it, with the same «has the list
/// been answered» flag the footer reads, and that the three states really are
/// three sentences in every language.
///
/// The filtered state is not reachable from here: the search term is the page's
/// own `@State` — deliberately, it is the one thing a person cannot retype — and
/// a test cannot write to that outside a render. It is `AppsEmptyTests`' to hold.
@MainActor
final class AnEmptyAppsTabSaysWhichEmptinessTests: XCTestCase {

    private let tool = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                    path: "/Applications/Tool.app", sizeBytes: 4_096)

    /// A page and the model behind it, wired to one transport.
    private func page(_ wire: UninstallerWire) -> (UninstallerSettingsPage, UninstallerViewModel) {
        let vm = ModuleViewModel(transport: wire)
        return (UninstallerSettingsPage(vm: vm), UninstallerViewModel.shared(vm: vm))
    }

    /// Both silences the wire has, folded to one nil by `TransportClient`.
    private static let silences = UninstallerWire.Answer.silences

    // MARK: -

    /// The claim: a list nobody answered is not a Mac with no applications on it,
    /// on the body as well as in the footer.
    func testAnUnansweredListIsNotDrawnAsAMacWithNoApps() async {
        for silence in Self.silences {
            let wire = UninstallerWire(apps: [tool], answering: silence)
            let (page, uvm) = page(wire)

            await uvm.loadAppsIfNeeded()

            XCTAssertTrue(wire.commands.contains(.listApps),
                          "precondition: the list really was asked for (\(silence))")
            XCTAssertEqual(page.appsEmpty, .neverAnswered, """
                the page says «\(UnStr.emptyMessage(.noApps))» about a Mac whose \
                applications Helm never managed to read (\(silence))
                """)
        }
    }

    /// The other half: an answer of «none» is an answer, and it reads as one.
    func testAnAnsweredEmptyListIsAMacWithNoApps() async {
        let wire = UninstallerWire(apps: [], answering: .reply)
        let (page, uvm) = page(wire)

        await uvm.loadAppsIfNeeded()

        XCTAssertTrue(uvm.listAnswered, "precondition: the engine answered")
        XCTAssertEqual(page.appsEmpty, .noApps)
    }

    /// And a list with rows on it is a list, not a statement.
    func testAListWithRowsSaysNothing() async {
        let wire = UninstallerWire(apps: [tool], answering: .reply)
        let (page, uvm) = page(wire)

        await uvm.loadAppsIfNeeded()

        XCTAssertEqual(uvm.apps.count, 1, "precondition: the list arrived")
        XCTAssertNil(page.appsEmpty)
    }

    /// The flag the footer reads and the flag the body reads are one flag. Two
    /// would drift, and the drift would be a page whose count says «Counting
    /// apps…» over a body claiming the Mac is empty. Which sentence the footer
    /// then draws is `AnUnansweredListIsNotAnEmptyMacTests`', so this holds the
    /// two halves rather than spelling that assertion again.
    func testTheBodyAndTheFooterReadTheSameAnswer() async {
        for silence in Self.silences {
            let wire = UninstallerWire(apps: [tool], answering: silence)
            let (_, uvm) = page(wire)

            await uvm.loadAppsIfNeeded()

            XCTAssertFalse(uvm.listAnswered, "(\(silence))")
            XCTAssertNil(uvm.appCount,
                         "the count claims to know something the body does not (\(silence))")
        }
    }

    /// Three reasons, three sentences — in every language, not in whichever one
    /// this machine is set to. A table that answered the same string twice would
    /// put the module back where it started with the type still in place.
    func testTheThreeReasonsAreThreeSentencesInEveryLanguage() {
        let reasons: [AppsEmpty.Reason] = [.neverAnswered, .noApps, .searchHidesAll]
        for language in AppLanguage.allCases {
            let said = reasons.map { UnStr.emptyMessage($0, language: language) }
            XCTAssertEqual(Set(said).count, reasons.count, """
                \(language.rawValue) draws the same sentence for more than one \
                reason: \(said)
                """)
            for sentence in said {
                XCTAssertFalse(sentence.isEmpty, "\(language.rawValue) says nothing")
            }
        }
    }

    /// The one sentence that must not be a claim about the Mac carries the
    /// program's name and its failure, in all eight — the English is the key, so
    /// a language that never got the row would read back the English here.
    func testTheUnansweredSentenceIsTranslatedEverywhere() {
        let english = UnStr.emptyMessage(.neverAnswered, language: .en)
        for language in AppLanguage.allCases where language != .en {
            XCTAssertNotEqual(UnStr.emptyMessage(.neverAnswered, language: language), english,
                              "\(language.rawValue) fell back to the English key")
        }
    }
}
