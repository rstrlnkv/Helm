import XCTest
import AppKit
import SwiftUI
import Foundation
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Two empty screens that must never be one sentence.**
///
/// `DoctorParser.parse` answers nil for "the tool said nothing" and `[]` for
/// "it ran and found nothing" — its own doc comment says so, and it says so
/// because the two are the same empty array everywhere downstream. The health
/// segment is where that distinction is finally drawn for a person: one of
/// those readings may be shown as a Mac with nothing wrong with it, and the
/// other may not. A machine nobody could examine is not a healthy machine, and
/// «Nothing to fix» over a refused query is this app telling somebody their Mac
/// is fine on the strength of an answer it never got.
///
/// The second half of the file is the fix, and the rule there is the opposite
/// kind of absence: a `.copyOnly` fix must draw **no button that acts**. That
/// one is read off a mounted page rather than off a value, because "the view
/// obeys the value" is exactly what a value-level assertion cannot see.
@MainActor
final class ARefusedDoctorIsNotAHealthyMacTests: XCTestCase {

    // MARK: - The fixture

    private static let deprecated = DoctorIssue(
        severity: .caution, title: "Some installed formulae are deprecated or disabled.",
        body: "You should find replacements for the following formulae:\n\n  periphery",
        fix: DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable))
    /// The same issue as the engine actually sends it — `fix: nil`, because
    /// `DoctorParser` never judges. What the page draws for it is decided by
    /// the Cellar the fixture puts under it and by nothing else.
    private static let unjudged = DoctorIssue(
        severity: .caution, title: deprecated.title, body: deprecated.body, fix: nil)
    /// The postflight block from this Mac's own output: real, and it proposes
    /// nothing at all.
    private static let postflight = DoctorIssue(
        severity: .danger,
        title: "Calling `postflight` is deprecated! Use `postflight_steps` instead.",
        body: "Please report this issue to the sozercan/homebrew-repo tap, or better, submit a PR:"
            + "\n  /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18",
        fix: nil)

    /// Answers `status` and the lists the page needs to draw at all, and answers
    /// `doctor` with whatever the test set — including **nothing**, which is how
    /// a refusal crosses this wire.
    private final class Clinic: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        /// The engine's own door for an operation's state, used here for the
        /// one state no launch produces: a fix judged again and refused.
        func emit(_ state: OpState) {
            stream.continuation.yield(EngineEvent(
                name: HomebrewEvent.opState.rawValue,
                payload: (try? JSONEncoder().encode(state)) ?? Data()))
        }

        private let lock = NSLock()
        private var _issues: [DoctorIssue]?
        private var _installed: [BrewPackage] = []
        /// What `brew list --versions` answers. The page judges a candidate
        /// against this, so it is part of the fixture rather than scenery.
        var installed: [BrewPackage] {
            get { lock.lock(); defer { lock.unlock() }; return _installed }
            set { lock.lock(); _installed = newValue; lock.unlock() }
        }
        /// nil means the engine could not answer — zero bytes on the wire, which
        /// is this codebase's one word for "the module could not answer".
        var issues: [DoctorIssue]? {
            get { lock.lock(); defer { lock.unlock() }; return _issues }
            set { lock.lock(); _issues = newValue; lock.unlock() }
        }
        init(issues: [DoctorIssue]?) { _issues = issues }

        private var _fired: [[String]] = []
        /// The argv the page put on the wire for `doctorFix`.
        var fired: [[String]] { lock.lock(); defer { lock.unlock() }; return _fired }
        /// Synchronous, and called from the `async` handler: taking an `NSLock`
        /// across a suspension point is unavailable from an asynchronous
        /// context, so the whole of the locked region is one call that cannot
        /// suspend inside it.
        private func record(_ argv: [String]) {
            lock.lock(); _fired.append(argv); lock.unlock()
        }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode(installed)
            case .outdated: return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions: return try JSONEncoder().encode([String: String]())
            case .doctor:
                guard let issues else { return Data() }
                return try JSONEncoder().encode(issues)
            case .doctorFix:
                if let argv = try? JSONDecoder().decode([String].self, from: command.payload) {
                    record(argv)
                }
                return Data()
            default: return Data()
            }
        }
    }

    private func model(_ issues: [DoctorIssue]?) -> (HomebrewViewModel, ModuleViewModel, Clinic) {
        let clinic = Clinic(issues: issues)
        let mvm = ModuleViewModel(transport: clinic)
        // `.shared`, not a fresh instance: `HomebrewSettingsPage(vm:)` reaches
        // the cache, so a view model built beside it is a second one the page
        // never reads — every mounted assertion below would then be about a
        // page showing the install screen.
        return (HomebrewViewModel.shared(vm: mvm), mvm, clinic)
    }

    // MARK: - The reading

    /// The three readings the module can be in, each answering its own screen.
    func testEachReadingAnswersItsOwnScreen() {
        XCTAssertEqual(HealthListState.of(.notAsked), .busy)
        XCTAssertEqual(HealthListState.of(.examined([])), .clean)
        XCTAssertEqual(HealthListState.of(.refused), .unexaminable)
        XCTAssertEqual(HealthListState.of(.examined([Self.deprecated])),
                       .rows([Self.deprecated]))
    }

    /// **The one assertion this file exists for.** An empty list that was
    /// *measured* and an empty list that was never taken are different screens,
    /// and nothing downstream can tell them apart once they are the same value.
    func testAnExaminedCleanMacAndAnUnexaminableOneAreNotTheSameScreen() {
        XCTAssertNotEqual(HealthListState.of(.examined([])), HealthListState.of(.refused), """
            a `brew doctor` that could not be asked reads as a Mac with nothing wrong with it — \
            the page says «Nothing to fix» about a question that was never answered
            """)
    }

    /// And the two sentences are different sentences, in all eight languages —
    /// two distinct states drawn with one string would pass the assertion above
    /// and still say the same thing to the person.
    func testTheTwoEmptyScreensSayDifferentThingsInEveryLanguage() {
        AppLanguage.each { language in
            XCTAssertNotEqual(HbStr.nothingToFix, HbStr.couldNotExamine,
                              "\(language.rawValue): one sentence for both empty screens")
            XCTAssertFalse(HbStr.couldNotExamine.isEmpty, "\(language.rawValue): nothing to say")
        }
    }

    // MARK: - What the query does to the reading

    func testAnEmptyAnswerIsAnExaminedMac() async {
        let (hb, _, _) = model([])
        await hb.refreshDoctor()
        XCTAssertEqual(hb.doctor, .examined([]))
        XCTAssertEqual(HealthListState.of(hb.doctor), .clean)
    }

    func testARefusedAnswerIsNotAnExaminedMac() async {
        let (hb, _, _) = model(nil)
        await hb.refreshDoctor()
        XCTAssertEqual(hb.doctor, .refused, """
            zero bytes on the wire — brew gone, the run cut off at the deadline, a tool that \
            printed nothing — was recorded as a `brew doctor` that ran and found nothing
            """)
    }

    /// **A refusal replaces the findings rather than keeping them.** The other
    /// three lists keep their last answer on a refusal, and this one may not:
    /// the list *is* the claim about the machine, so two issues left on screen
    /// under a reading that failed state that those two are still what is wrong.
    func testARefusalDoesNotLeaveTheLastFindingsOnScreen() async {
        let (hb, _, clinic) = model([Self.deprecated, Self.postflight])
        await hb.refreshDoctor()
        XCTAssertEqual(hb.issues.count, 2, "precondition: the findings were read")

        clinic.issues = nil
        await hb.refreshDoctor()
        XCTAssertEqual(hb.issues, [], """
            a refused reading kept the previous findings, so the page goes on naming two things \
            wrong with a Mac it has just failed to examine
            """)
        XCTAssertEqual(HealthListState.of(hb.doctor), .unexaminable)
    }

    /// And a selection does not outlive the finding it stands for — the rule
    /// every other segment already carries, since a stale finding on screen has
    /// a live button under it.
    func testARefusalDropsTheSelection() async {
        let (hb, _, clinic) = model([Self.deprecated])
        hb.segment = .health
        await hb.refreshDoctor()
        hb.select(Self.deprecated.id)
        XCTAssertEqual(hb.selected, Self.deprecated.id, "precondition: the selection was made")

        clinic.issues = nil
        await hb.refreshDoctor()
        XCTAssertNil(hb.selected, "the inspector still describes a finding nothing answered for")
    }

    // MARK: - The verdict the page draws

    /// **The page judges the candidate against the Cellar it holds, and the
    /// verdict is the only thing that moves.**
    ///
    /// `DoctorParser` always answers `fix: nil` — a command read out of a
    /// tool's output is data until it has been judged — so the fix on screen is
    /// one `refreshDoctor` built by handing the body to
    /// `DoctorFixCandidate.judging`. The two readings below carry the *same
    /// body and the same argv*; only the installed list differs, and only
    /// `DoctorFix.kind` may differ in the answer.
    func testThePageJudgesTheCandidateAgainstTheInstalledListItHolds() async {
        /// A `brew doctor` whose issues arrive unjudged, the way the engine
        /// sends them, over a Cellar the test chooses.
        func judged(_ cellar: [String]) async -> DoctorFix? {
            let clinic = Clinic(issues: [DoctorIssue(severity: .caution,
                                                     title: Self.deprecated.title,
                                                     body: Self.deprecated.body, fix: nil)])
            clinic.installed = cellar.map { BrewPackage(name: $0, version: "1.0.0", isCask: false) }
            let mvm = ModuleViewModel(transport: clinic)
            let hb = HomebrewViewModel.shared(vm: mvm)
            await hb.refreshDoctor()
            return hb.issues.first?.fix
        }

        let here = await judged(["periphery", "wget"])
        XCTAssertEqual(here, DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable), """
            the body names a formula this Mac has and the page drew no runnable fix — the \
            candidate was never built, or it was never judged
            """)
        let gone = await judged(["wget"])
        XCTAssertEqual(gone, DoctorFix(argv: ["uninstall", "periphery"], kind: .copyOnly), """
            the same body against a Cellar without periphery came back runnable: the judge was \
            bypassed, or it was handed a list that is not the one the page holds
            """)
    }

    /// **The installed list is read before the verdict is taken.** Opening this
    /// segment first on a fresh launch finds that list unread, and a verdict
    /// taken then says `.copyOnly` because the page has no Cellar rather than
    /// because the name is not in it — a withheld button justified by nothing.
    func testTheVerdictIsNotTakenAgainstAListThatWasNeverRead() async {
        let clinic = Clinic(issues: [DoctorIssue(severity: .caution, title: Self.deprecated.title,
                                                 body: Self.deprecated.body, fix: nil)])
        clinic.installed = [BrewPackage(name: "periphery", version: "1.0.0", isCask: false)]
        let mvm = ModuleViewModel(transport: clinic)
        let hb = HomebrewViewModel.shared(vm: mvm)
        // No `loadIfNeeded`: this is the page opened straight onto Health.
        XCTAssertFalse(hb.loadedInstalled, "precondition: nothing has read the Cellar yet")

        await hb.refreshDoctor()
        XCTAssertEqual(hb.issues.first?.fix?.kind, .runnable, """
            the verdict was taken against an installed list nobody had read, so a fix Helm may \
            run was drawn without its button on every first visit to this segment
            """)
    }

    /// **What is copied and what is sent are two different strings.**
    ///
    /// The well shows `brew uninstall periphery`, because a person pasting it
    /// into Terminal needs the executable's name. The wire carries
    /// `["uninstall", "periphery"]`, because that is the shape
    /// `DoctorFix.judge` recognises — its doc comment says an argv still
    /// carrying `brew` at the front "has not been parsed" and is `.copyOnly`.
    /// So a page that sent what it displayed would hand the engine a command it
    /// refuses every time, and the button would silently never work.
    func testThePressSendsTheArgvAndNotTheLineOnScreen() async {
        let clinic = Clinic(issues: [Self.unjudged])
        clinic.installed = [BrewPackage(name: "periphery", version: "1.0.0", isCask: false)]
        let hb = HomebrewViewModel.shared(vm: ModuleViewModel(transport: clinic))
        await hb.refreshDoctor()
        guard let fix = hb.issues.first?.fix else { return XCTFail("no fix was drawn") }
        XCTAssertEqual(fix.kind, .runnable, "precondition: this is the fix with a button on it")

        hb.runDoctorFix(fix)
        for _ in 0..<20 where clinic.fired.isEmpty { await Task.yield() }
        XCTAssertEqual(clinic.fired, [["uninstall", "periphery"]], """
            the page sent something other than the judged argv — `DoctorFix.judge` refuses \
            anything with `brew` at the front, so the engine would decline every press and the \
            button would do nothing at all: \(clinic.fired)
            """)
    }

    // MARK: - Every segment is reachable

    /// The picker is built from `Segment.allCases` and `Segment.label`, so a
    /// case with no word is a build error rather than a segment nothing can
    /// reach. This names all four, so adding a fifth sends its author here.
    func testEverySegmentIsNamedAndNamedDistinctly() {
        XCTAssertEqual(HomebrewViewModel.Segment.allCases,
                       [.installed, .updates, .search, .health])
        AppLanguage.each { language in
            let words = HomebrewViewModel.Segment.allCases.map(\.label)
            XCTAssertEqual(Set(words).count, words.count,
                           "\(language.rawValue): two segments share a word — \(words)")
            XCTAssertFalse(words.contains(where: \.isEmpty), "\(language.rawValue): an unnamed segment")
        }
    }

    // MARK: - The refusal reaches the page

    /// **Every reason the engine can name has a sentence, or is one the page
    /// draws its own pill for.**
    ///
    /// The console's note was an `if` against one reason, so a second one drew
    /// a bare «Failed» with nothing saying why — a refusal reaching the page as
    /// an empty fact. `.stopped` is the only nil, and it is nil because the arm
    /// above draws its own pill for it: the person asked for that end.
    func testEveryFailureReasonHasSomethingToSay() {
        AppLanguage.each { language in
            for reason in OpFailureReason.allCases where reason != .stopped {
                let note = HomebrewSettingsPage.failureNote(reason)
                XCTAssertNotNil(note, """
                    \(language.rawValue): \(reason.rawValue) draws «Failed» and no reason, so \
                    the person is told the operation failed and nothing about why
                    """)
                XCTAssertFalse(note?.isEmpty ?? true, "\(language.rawValue): \(reason.rawValue)")
            }
            let notes = OpFailureReason.allCases.compactMap(HomebrewSettingsPage.failureNote)
            XCTAssertEqual(Set(notes).count, notes.count, """
                \(language.rawValue): two reasons share a sentence, so the page says the same \
                thing about brew vanishing and about a command it judged again and refused
                """)
        }
    }

    /// And the console it is drawn in is on the page at all. A refusal is
    /// emitted before anything launches, so it writes no output line — with the
    /// console gated on having output, the whole report had nowhere to appear.
    func testARefusalIsDrawnEvenWithNothingInTheConsole() async {
        let (hb, mvm, clinic) = model([])
        await hb.loadIfNeeded()
        XCTAssertTrue(hb.consoleLines.isEmpty, "precondition: nothing has been written")

        let idle = MountedRender(HomebrewSettingsPage(vm: mvm),
                                 width: 900, height: 700, appearance: .aqua)
        idle.settle(20)
        let quiet = idle.host.everyView.count
        idle.drop()

        clinic.emit(OpState(phase: .failed, label: "uninstall periphery", reason: .fixRefused))
        // The view model consumes the stream on a task of its own; a turn of
        // the loop is what delivers it.
        for _ in 0..<20 where hb.op.phase != .failed { await Task.yield() }
        XCTAssertEqual(hb.op.reason, .fixRefused, "the refusal never reached the view model")
        let failed = MountedRender(HomebrewSettingsPage(vm: mvm),
                                   width: 900, height: 700, appearance: .aqua)
        failed.settle(20)
        let loud = failed.host.everyView.count
        failed.drop()

        XCTAssertGreaterThan(loud, quiet, """
            a refused fix drew nothing at all: the console is where the reason goes and it was \
            gated on there being output, which a refusal before the launch never produces
            """)
    }

    // MARK: - The fix, read off a mounted page

    /// Every focus ring on the health screen with `issue` selected — which is
    /// what a bordered control is in this tree, and the reading
    /// `TheNarrowBandActsInEverySegmentTests` already takes for the same
    /// question. A SwiftUI `Button` is not an `NSButton` here: it hosts as
    /// `SwiftUIAppKitButton` with no title to read, so the count is what there
    /// is to measure and the counts below are read against each other.
    ///
    /// The appearance is named, for `RenderedInk`'s reason — an unnamed one is
    /// a reading of whatever this Mac is set to at this hour. The width is well
    /// above `HomebrewSplit`'s threshold, so the list and the finding are side
    /// by side and both are mounted.
    private func rings(_ issues: [DoctorIssue], selecting issue: DoctorIssue?,
                       cellar: [String] = []) async -> Int {
        let (hb, mvm, clinic) = model(issues)
        clinic.installed = cellar.map { BrewPackage(name: $0, version: "1.0.0", isCask: false) }
        await hb.loadIfNeeded()
        hb.segment = .health
        await hb.refreshDoctor()
        hb.select(issue?.id)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: 900, height: 700, appearance: .aqua)
        mount.settle(25)
        let count = mount.host.everyView(named: "_FocusRingView").count
        mount.drop()
        return count
    }

    /// **The three shapes, measured against each other in one test.**
    ///
    /// Separately they would each be an assertion about an absolute count of
    /// controls on a page that has a picker, a Refresh and a list on it — a
    /// number that moves for reasons that have nothing to do with this feature.
    /// Read as differences they say only what this feature decides: a finding
    /// that proposes nothing offers nothing, a command Helm may not run offers
    /// one thing, and a command it may run offers two.
    ///
    /// Each absence is asserted beside a presence, which is the whole reason
    /// the three are one test: `noFix` is the baseline that proves the page can
    /// draw these controls at all, so «no button that acts» below is an absence
    /// of something known to be drawable and not of something no page draws.
    func testWhatEachKindOfFixOffers() async {
        // One body, arriving unjudged the way the engine sends it, and three
        // Cellars: the page's own verdict is what differs between the last two.
        let noFix = await rings([Self.postflight], selecting: Self.postflight)
        let copyOnly = await rings([Self.unjudged], selecting: Self.unjudged, cellar: ["wget"])
        let runnable = await rings([Self.unjudged], selecting: Self.unjudged,
                                   cellar: ["periphery"])

        XCTAssertEqual(copyOnly, noFix + 1, """
            a copy-only fix drew \(copyOnly - noFix) control(s) where it must draw exactly one, \
            the copy: a well with nothing to do beside it is a promise this page cannot keep, \
            and two would mean something on the page will run a command the judge refused
            """)
        XCTAssertEqual(runnable, noFix + 2, """
            a runnable fix drew \(runnable - noFix) control(s) where it must draw two — the copy \
            and the button that acts. If this is one, the fix Helm may run has no way to run it
            """)
        // Said outright, because it is the sentence the feature turns on and the
        // two assertions above are arithmetic about it.
        XCTAssertLessThan(copyOnly, runnable, """
            the argv is byte-for-byte the same in both readings and only `DoctorFix.kind` \
            differs, so a page drawing the same controls for the two is drawing the command \
            rather than the judgement
            """)
    }

    /// And the two controls are two different words, in all eight languages: a
    /// count of two is not a proof of two *distinct* offers.
    func testTheTwoAffordancesAreNotOneWord() {
        AppLanguage.each { language in
            XCTAssertNotEqual(HbStr.runTheFix, HbStr.copyTheFix,
                              "\(language.rawValue): one word for running and for copying")
        }
    }

    /// **Nothing on this screen attributes the command to Homebrew.**
    ///
    /// Measured on this Mac (Homebrew 7.0.1, 2026-09-15) and recorded in
    /// `DoctorFixCandidate`'s doc comment: `brew doctor` printed 1,194 bytes and
    /// not one `brew …` command line. `uninstall <name>` is Helm reading a
    /// heading brew printed, so a label saying Homebrew suggested it would put
    /// this app's own decision in somebody else's mouth — and the reader who
    /// would act on that is the one who trusted Homebrew rather than Helm.
    func testTheFixIsNeverAttributedToHomebrew() {
        AppLanguage.each { language in
            for word in [HbStr.helmReadsThisAs, HbStr.runTheFix, HbStr.copyTheFix] {
                XCTAssertFalse(word.contains("Homebrew"), """
                    \(language.rawValue): \(word.debugDescription) names Homebrew over a command \
                    Homebrew never printed
                    """)
            }
            // The provenance sentence does name Homebrew, and has to — it is
            // the one that says brew named no command. It must not, though, be
            // empty, because an unwritten provenance is the same as none.
            XCTAssertTrue(HbStr.brewNamedNoCommand.contains("Homebrew"), """
                \(language.rawValue): the sentence that exists to say what Homebrew did and did \
                not print no longer names it
                """)
        }
    }
}
