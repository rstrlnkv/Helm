import XCTest
import HelmContract
import HelmUI
import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The master and the bar under it, on one screen, about one fact.**
///
/// `ARefusedListIsNotAnEmptyOneTests` gave the *list* a third sentence, and
/// `statusLine` kept a `Bool`: it read `loadedInstalled`, which is
/// `installedReading == .answered` and therefore false for `.waiting` and for
/// `.unanswerable` alike. Before that repair both halves lied the same way and
/// the page was at least consistent; after it, one 984 pt pane carried
/// «Homebrew не ответил, поэтому об установленных пакетах сейчас ничего не
/// известно.» with its ink at y 357.5…389.5 and «Читаем список пакетов…» 327 pt
/// below it at y 716.5…730.5 — measured 2026-09-16 — and CLAUDE.md's rule about
/// one screen carrying two accounts of one fact says the quieter of the two is
/// the one that gets believed.
///
/// **What this asserts is agreement, not vocabulary.** A case that asked
/// whether the bar "says something about a refusal" passes over a bar that says
/// it always, and a whole family of this module's briefs has been caught doing
/// exactly that. So the subject here is the *pairing*: for each reading the
/// list can be in, the sentence in the bar must be the one that belongs to the
/// screen the list is drawing — the loading sentence exactly when the list is
/// waiting, the refusal exactly when the list is unanswerable, and a count in
/// neither case. Three readings, three sentences, and each one wrong in at
/// least one direction if any pair is folded together.
@MainActor
final class OneScreenTellsOneStoryTests: XCTestCase {

    /// Refuses the list and answers everything else — the wire's "could not
    /// answer" is zero bytes, which is what a `brew` cut off at the runner's
    /// deadline sends, and `refreshInstalled` reads it as a refusal rather than
    /// as an empty Cellar.
    private final class ListRefuses: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return Data()
            default:
                return Data("[]".utf8)
            }
        }
    }

    /// Answers the list with an empty Cellar — a real answer that happens to
    /// hold nothing, which is the state the refusal above must not be drawn as.
    private final class CellarIsEmpty: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            default:
                return Data("[]".utf8)
            }
        }
    }

    /// **The claim.** In every language — this Mac runs in Russian, so a bare
    /// assertion exercises one of eight — the bar's sentence is the one that
    /// belongs to the screen the master is drawing.
    func testTheBarSaysWhatTheListIsDrawingInEveryLanguage() async {
        let refused = ModuleViewModel(transport: ListRefuses())
        let refusedPage = HomebrewSettingsPage(vm: refused)
        let refusedModel = HomebrewViewModel.shared(vm: refused)

        // Before anything is asked: the list is waiting and so is the bar.
        // Asserted first, so "the bar is not the loading sentence" below is a
        // change rather than a state that was never entered.
        XCTAssertEqual(refusedModel.installedReading, .notAsked,
                       "precondition: nothing has been asked yet")
        XCTAssertEqual(ListScreen.of(isEmpty: true, reading: refusedModel.installedReading),
                       .waiting, "precondition: the list draws its wait before the first ask")
        AppLanguage.each { language in
            XCTAssertEqual(refusedPage.statusLine, HbStr.packagesLoading, """
                \(language.rawValue): before the first query the list draws its wait and the \
                bar says \(refusedPage.statusLine) — the two halves of the pane disagree \
                about whether anything has been asked
                """)
        }

        await refusedModel.refreshInstalled()
        XCTAssertEqual(refusedModel.installedReading, .unanswerable,
                       "precondition: a refused list with nothing behind it is unanswerable")
        XCTAssertEqual(ListScreen.of(isEmpty: refusedModel.installed.isEmpty,
                                     reading: refusedModel.installedReading),
                       .unanswerable, "precondition: the master draws the refusal")
        AppLanguage.each { language in
            XCTAssertEqual(refusedPage.statusLine, HbStr.couldNotCount, """
                \(language.rawValue): the master says Homebrew did not answer and the bar \
                under it says \(refusedPage.statusLine) — one screen, two accounts of one \
                fact, and the quieter one is the one that gets believed
                """)
            XCTAssertNotEqual(refusedPage.statusLine, HbStr.packagesLoading,
                              "\(language.rawValue): the bar is still reading a list nobody can read")
        }

        // And the other empty screen, which must not take the refusal's
        // sentence: a Cellar that answered and holds nothing is a count of
        // zero, not a refusal.
        let empty = ModuleViewModel(transport: CellarIsEmpty())
        let emptyPage = HomebrewSettingsPage(vm: empty)
        let emptyModel = HomebrewViewModel.shared(vm: empty)
        await emptyModel.refreshInstalled()
        await emptyModel.refreshOutdated()
        XCTAssertEqual(emptyModel.installedReading, .answered,
                       "precondition: an empty answer is an answer")
        AppLanguage.each { language in
            XCTAssertEqual(emptyPage.statusLine, HbStr.packagesStatus(0, 0, 0), """
                \(language.rawValue): an answered, empty Cellar draws \(emptyPage.statusLine) \
                where it has a count to give — the refusal's sentence has been widened over \
                a state that measured something
                """)
        }
    }

    /// **And the three sentences are three sentences**, in all eight. A bar
    /// that answered "Homebrew did not answer." to every reading would pass the
    /// pairing above only if the pairing is real; this is the cheaper half of
    /// the same claim, and it is the one that fails loudest when a translation
    /// is missing and two keys fall back to one English string.
    func testTheBarsThreeSentencesAreThreeSentencesInEveryLanguage() {
        AppLanguage.each { language in
            let said = [HbStr.packagesLoading, HbStr.couldNotCount, HbStr.packagesStatus(0, 0, 0)]
            XCTAssertEqual(Set(said).count, said.count, """
                \(language.rawValue): the status bar says the same thing about two different \
                readings of the package list — \(said)
                """)
            XCTAssertFalse(said.contains(where: \.isEmpty),
                           "\(language.rawValue): the bar has a reading with nothing to say")
            // Not the master's own sentence said twice, either: the long one
            // names what is not known and this one is the bar with no count.
            XCTAssertNotEqual(HbStr.couldNotCount, HbStr.couldNotList, """
                \(language.rawValue): the bar repeats the master's whole sentence rather than \
                saying why it has no counts
                """)
        }
    }
}
