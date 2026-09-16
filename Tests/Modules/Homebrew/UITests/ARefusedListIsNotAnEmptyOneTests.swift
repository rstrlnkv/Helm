import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **A `brew` that refuses is not an empty Cellar, and it is not "still
/// loading" either.**
///
/// `refreshDoctor`'s own doc comment states the rule this module lives by: "no
/// issues" and "the question could not be put" are the same empty array and
/// must never be the same sentence on screen. Состояние honoured it —
/// `DoctorReading` has a case per outcome — and the other three lists did not:
/// each had a `Bool`, and a `Bool` holds two of the three things that happen to
/// a query. A refused `brew list` left the flag down, so the page drew
/// `HelmBusyState` — a 16×16 pt spinner and «Reading the package list…» — and
/// went on drawing it, with no timeout anywhere in the UI.
///
/// **Why the rendering half is here at all.** A test that asserts the refusal
/// sentence is drawn passes just as well over a page that draws that sentence
/// *always*. So the claim is a difference: the honestly-empty pane and the
/// refused pane must not be the same drawing, and only one of the three states
/// may have anything moving in it.
@MainActor
final class ARefusedListIsNotAnEmptyOneTests: XCTestCase {

    // MARK: - The decision

    /// The table, read as a table. Every pairing of "are there rows" with each
    /// reading, so a case folded into its neighbour is a diff rather than a
    /// silence.
    func testEveryReadingOfAnEmptyListIsItsOwnScreen() {
        XCTAssertEqual(ListScreen.of(isEmpty: true, reading: .notAsked), .waiting)
        XCTAssertEqual(ListScreen.of(isEmpty: true, reading: .waiting), .waiting)
        XCTAssertEqual(ListScreen.of(isEmpty: true, reading: .answered), .nothing)
        XCTAssertEqual(ListScreen.of(isEmpty: true, reading: .unanswerable), .unanswerable, """
            a refused query draws the same screen as an answered one — which is \
            «No packages installed.» over a Cellar nobody could read
            """)
    }

    /// Rows are an answer somebody got, whatever the last query did. This is
    /// the module's own rule about keeping the last answer, stated as a screen.
    func testRowsAreDrawnWhateverTheLastQueryDid() {
        for reading: ListReading in [.notAsked, .waiting, .answered, .unanswerable] {
            XCTAssertEqual(ListScreen.of(isEmpty: false, reading: reading), .rows,
                           "rows on screen were replaced by a sentence for reading \(reading)")
        }
    }

    // MARK: - The three sentences

    /// Three states need three sentences, in each of the eight languages — a
    /// pair that collapses in one language is a pair that collapses, and this
    /// Mac runs in Russian, so a bare assertion would exercise one of eight.
    func testTheThreeSentencesAreThreeSentencesInEveryLanguage() {
        AppLanguage.each { language in
            for (name, said) in [("installed", [HbStr.packagesLoading, HbStr.noneInstalled, HbStr.couldNotList]),
                                 ("updates", [HbStr.checkingForUpdates, HbStr.upToDate, HbStr.couldNotCheckForUpdates]),
                                 ("search", [HbStr.searching, HbStr.noResults, HbStr.couldNotSearch])] {
                XCTAssertEqual(Set(said).count, said.count, """
                    \(language.rawValue): the \(name) list says the same thing about two \
                    different states — \(said)
                    """)
                XCTAssertFalse(said.contains(where: \.isEmpty),
                               "\(language.rawValue): the \(name) list has a state with nothing to say")
            }
        }
    }

    // MARK: - The readings the view model takes

    /// Answers what it is told to and refuses the rest, so "the query could not
    /// be put" is a real trip through the transport rather than a field set by
    /// hand.
    private final class Cellar: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        /// nil means «refuse» — which is what the client reads as an empty
        /// answer, the state this whole file is about.
        var installed: [BrewPackage]?
        var outdated: [OutdatedPackage]?
        var hits: [SearchHit]?
        /// Commands that never answer, for the one state that is allowed to
        /// spin.
        var hanging: Set<String> = []

        init(installed: [BrewPackage]? = [], outdated: [OutdatedPackage]? = [],
             hits: [SearchHit]? = []) {
            self.installed = installed
            self.outdated = outdated
            self.hits = hits
        }

        func send(_ command: EngineCommand) async throws -> Data {
            if hanging.contains(command.name) {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            }
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                guard let installed else { throw CancellationError() }
                return try JSONEncoder().encode(installed)
            case .outdated:
                guard let outdated else { throw CancellationError() }
                return try JSONEncoder().encode(outdated)
            case .search:
                guard let hits else { throw CancellationError() }
                return try JSONEncoder().encode(hits)
            case .descriptions:
                return try JSONEncoder().encode([String: String]())
            default:
                return Data()
            }
        }
    }

    private static let wget = BrewPackage(name: "wget", version: "1.25.0", isCask: false)

    func testARefusedFirstListIsUnanswerableAndNotStillLoading() async {
        let transport = Cellar(installed: nil)
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        await model.refreshInstalled()

        XCTAssertEqual(model.installedReading, .unanswerable, """
            a `brew list` that refused left the reading at \(model.installedReading) — which is \
            the spinner, for ever, because nothing in the UI asks again
            """)
        XCTAssertEqual(ListScreen.of(isEmpty: model.installed.isEmpty,
                                     reading: model.installedReading), .unanswerable)
    }

    /// And the same for the other two, since each had its own flag or none.
    func testARefusedUpdatesQueryAndARefusedSearchSayWhatHappened() async {
        let transport = Cellar(outdated: nil, hits: nil)
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))

        await model.refreshOutdated()
        XCTAssertEqual(model.outdatedReading, .unanswerable)

        await model.search("zzz")
        XCTAssertEqual(model.searchReading, .unanswerable, """
            a refused `brew search` left the reading at \(model.searchReading), which the page \
            draws as «No results.» — the answer to the question, over a question that was refused
            """)
    }

    /// **A refusal on top of an answer keeps the answer, and says so.** The
    /// three lists keep their last reply on purpose ("no `?? []` on any list
    /// reply"), and the reading has to keep describing what is on screen —
    /// otherwise the status line's counts vanish behind a sentence about a
    /// query nobody can see.
    func testARefusalOnTopOfAnAnswerKeepsBoth() async {
        let transport = Cellar(installed: [Self.wget])
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        await model.refreshInstalled()
        XCTAssertEqual(model.installedReading, .answered, "precondition: the first list landed")

        transport.installed = nil
        await model.refreshInstalled()

        XCTAssertEqual(model.installed.map(\.name), ["wget"], """
            the refusal replaced a real package list with nothing, which is the defect \
            `ATimedOutQueryKeepsTheLastAnswerTests` is about
            """)
        XCTAssertEqual(model.installedReading, .answered, """
            the reading went to \(model.installedReading) over a list that is still on screen, \
            so the page would put a sentence about an unread Cellar over the rows of one
            """)
        XCTAssertTrue(model.loadedInstalled, "the counts belong to an answer that is still drawn")
    }

    // MARK: - What the pane actually draws

    private func mount(_ transport: Cellar, width: CGFloat = 984) async -> MountedRender {
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        let page = HomebrewSettingsPage(vm: mvm)
        let mount = MountedRender(page, width: width, height: 560, appearance: .aqua)
        let loading = Task { @MainActor in await hb.loadIfNeeded() }
        for _ in 0..<60 {
            mount.host.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
        _ = loading
        return mount
    }

    private func spinners(_ mount: MountedRender) -> Int {
        mount.host.everyView(ofType: NSProgressIndicator.self).count
    }

    /// **The list pane's own band, and not the page.** The mount is 560 pt tall:
    /// the segment bar and its divider take the top 49 and the status line takes
    /// the bottom 49, and that line is *not* the same in these three cases — it
    /// says «Reading the package list…» until a count has arrived. Compared whole,
    /// two pages differ because of the status bar whatever the pane says, and the
    /// check passes for the wrong reason. Measured 2026-09-16: with the defect
    /// deliberately back in — the refusal sentence drawn over an empty Cellar as
    /// well — the whole-page comparison passed.
    private static let paneBand = 60...460

    private func picture(_ mount: MountedRender) -> Data? {
        mount.pixels(Self.paneBand)
    }

    /// **Three states, three drawings.** Waiting moves; the two answers do not
    /// and are not the same picture.
    ///
    /// The subject is asserted before the absence, twice over: the waiting pane
    /// has to have a spinner in it at all, or "the refused pane has none" is
    /// true of a page that drew nothing; and the two still panes have to differ,
    /// or "the refusal says its own sentence" is true of a page that says that
    /// sentence always.
    func testTheWaitMovesAndNeitherAnswerDoes() async {
        let waiting = Cellar(installed: [])
        waiting.hanging = [HomebrewCommand.listInstalled.rawValue]
        let onWait = await mount(waiting)
        let spinning = spinners(onWait)
        let waitingPicture = picture(onWait)
        onWait.drop()

        let empty = await mount(Cellar(installed: []))
        let emptySpinners = spinners(empty)
        let emptyPicture = picture(empty)
        empty.drop()

        let refused = await mount(Cellar(installed: nil))
        let refusedSpinners = spinners(refused)
        let refusedPicture = picture(refused)
        refused.drop()

        XCTAssertGreaterThan(spinning, 0, """
            the pane waiting on `brew list` has nothing moving in it, so the two readings \
            below are not measurements of anything
            """)
        XCTAssertEqual(emptySpinners, 0, "an answered, empty Cellar is not something to wait for")
        XCTAssertEqual(refusedSpinners, 0, """
            the refused pane is still drawing \(refusedSpinners) progress indicator(s) — nothing \
            is on its way and nothing will ask again, so this is the spinner that never stops
            """)

        XCTAssertNotNil(emptyPicture)
        XCTAssertNotNil(refusedPicture)
        XCTAssertNotEqual(emptyPicture, refusedPicture, """
            an answered-and-empty Cellar and a refused one are drawn pixel for pixel the same, \
            so whatever sentence is on screen is on screen for both of them
            """)
        XCTAssertNotEqual(waitingPicture, emptyPicture,
                          "the wait and the empty answer are one drawing")
    }
}
