import XCTest
import AppKit
import SwiftUI
import Foundation
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The Health tab is a verdict, the findings behind it, and the configuration —
/// and none of the three may swallow another.**
///
/// It was a list of findings and configuration groups with an inspector beside
/// it. It is one page now (`HomebrewHealthPage`), and the ways to lose something
/// moved with it:
///
/// - the configuration swallowing the verdict — «Homebrew did not answer» is the
///   line a person decides whether to trust their Mac on, and a page with a
///   configuration card on it must still say it;
/// - the findings swallowing the configuration — a refused `brew doctor` says
///   nothing whatever about `brew config`;
/// - the search field swallowing the verdict — a word typed over the page must
///   not be able to say a Mac is clean, which is why the verdict is read off the
///   unfiltered reading;
/// - a closed finding taking room, or an open one taking none — the reveal is
///   `helmAccordion`'s measured height, and a measurement that never lands is
///   a row whose body is there and is zero points tall.
@MainActor
final class TheHealthPageIsAVerdictAndTwoCardsTests: XCTestCase {

    // MARK: - The fixture

    /// A trimmed but real reading: two lines per group, brew's own keys, and
    /// the whole document beside them the way the engine sends it.
    private static let document = """
        HOMEBREW_VERSION: 7.0.1
        CPU: 11-core 64-bit arm_lobos
        Clang: 21.0.0 build 2100
        HOMEBREW_PREFIX: /opt/homebrew
        macOS: 27.0-arm64
        Xcode: 27.0
        """

    private static var lines: [ConfigLine] { BrewConfigParser.parse(document) ?? [] }
    private static var config: BrewConfig { BrewConfig(lines: lines, text: document) }
    private static var groups: [ConfigGroup] { ConfigGroup.grouping(lines) }

    private static let finding = DoctorIssue(
        severity: .caution, title: "Some installed formulae are deprecated or disabled.",
        body: "You should find replacements for the following formulae:\n\n  periphery",
        fix: nil)
    private static let second = DoctorIssue(
        severity: .caution, title: "You have unlinked kegs in your Cellar.",
        body: "Run `brew link` on these:\n  python@3.12", fix: nil)

    /// Answers `status`, the lists the page needs, `doctor` and `config` —
    /// each of the last two settable to nothing, which is how a refusal crosses
    /// this wire.
    private final class Bench: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        private let lock = NSLock()
        private var _issues: [DoctorIssue]?
        private var _config: BrewConfig?
        /// nil means the engine could not answer — zero bytes on the wire.
        var issues: [DoctorIssue]? {
            get { lock.lock(); defer { lock.unlock() }; return _issues }
            set { lock.lock(); _issues = newValue; lock.unlock() }
        }
        var config: BrewConfig? {
            get { lock.lock(); defer { lock.unlock() }; return _config }
            set { lock.lock(); _config = newValue; lock.unlock() }
        }
        init(issues: [DoctorIssue]?, config: BrewConfig?) { _issues = issues; _config = config }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([BrewPackage]())
            case .outdated: return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions: return try JSONEncoder().encode([String: String]())
            case .doctor:
                guard let issues else { return Data() }
                return try JSONEncoder().encode(issues)
            case .config:
                guard let config else { return Data() }
                return try JSONEncoder().encode(config)
            default: return Data()
            }
        }
    }

    private func model(issues: [DoctorIssue]?, config: BrewConfig?)
        -> (HomebrewViewModel, ModuleViewModel, Bench) {
        let bench = Bench(issues: issues, config: config)
        let mvm = ModuleViewModel(transport: bench)
        // `.shared`, for the reason `ARefusedDoctorIsNotAHealthyMacTests` gives:
        // the page reaches the cache, so a view model built beside it is one
        // the page never reads.
        return (HomebrewViewModel.shared(vm: mvm), mvm, bench)
    }

    // MARK: - The grouping

    /// The three groups in the drawing's order, each keeping brew's own order
    /// inside it. Order is the assertion because `Dictionary(grouping:)` is the
    /// obvious way to write this and answers in hash order — three headings
    /// that change places between launches, and lines that do too.
    func testTheGroupsComeBackInTheDrawingsOrderWithBrewsOwnOrderInside() {
        let groups = Self.groups
        XCTAssertEqual(groups.map(\.section), [.brew, .machine, .tools])
        XCTAssertEqual(groups.map { $0.lines.map(\.key) },
                       [["HOMEBREW_VERSION", "HOMEBREW_PREFIX"],
                        ["CPU", "macOS"],
                        ["Clang", "Xcode"]])
    }

    /// A heading with nothing under it is not a heading. A machine whose
    /// `brew config` named no tool draws two groups, not three with an empty
    /// one that looks like a reading that came back blank.
    func testAGroupWithNoLinesIsNotDrawn() {
        let only = ConfigGroup.grouping([ConfigLine(key: "CPU", value: "x", section: .machine)])
        XCTAssertEqual(only.map(\.section), [.machine])
    }

    /// Ids are distinct across the two kinds of thing. A `DoctorIssue`'s id is
    /// built from its own text; a group's is `cfg:` and a case name.
    func testAGroupsIdCannotCollideWithAFindingsOrAPackagesID() {
        let ids = Set(Self.groups.map(\.id))
        XCTAssertEqual(ids.count, 3)
        XCTAssertFalse(ids.contains(Self.finding.id))
        XCTAssertFalse(ids.contains(BrewKey.of(name: "brew", isCask: false)))
    }

    // MARK: - What the screen is

    /// Every reading of `brew doctor` has its own verdict, whatever
    /// `brew config` did — the four answers the module can be in, none of them
    /// made from another.
    func testEveryDoctorReadingHasItsOwnVerdictBesideTheConfiguration() {
        for config in [[], Self.groups] {
            XCTAssertEqual(HealthScreen.of(.notAsked, config: config).verdict, .checking)
            XCTAssertEqual(HealthScreen.of(.examined([]), config: config).verdict, .clean)
            XCTAssertEqual(HealthScreen.of(.refused, config: config).verdict, .unexaminable)
            XCTAssertEqual(HealthScreen.of(.examined([Self.finding, Self.second]),
                                           config: config).verdict, .findings(2))
        }
    }

    /// **The one assertion the old version of this file existed for.** A
    /// `brew doctor` that could not be asked still leaves a configuration that
    /// could, and the verdict saying why there are no findings has to survive
    /// beside it. Collapsing either way loses something a person needs: the
    /// sentence, or every group that was read successfully.
    func testARefusedDoctorKeepsBothItsVerdictAndTheConfiguration() {
        let screen = HealthScreen.of(.refused, config: Self.groups)
        XCTAssertEqual(screen.verdict, .unexaminable, """
            the verdict explaining why there are no findings did not survive the configuration \
            being on the page — «nothing is known about this Mac» is the line a person decides \
            whether to trust the app on
            """)
        XCTAssertEqual(screen.configuration, Self.groups, "the configuration was thrown away with the findings")
        XCTAssertEqual(screen.findings, [])
        XCTAssertFalse(screen.noMatches, "a refusal is not a filter hiding findings")
    }

    /// Findings and configuration on one page, each in its own card.
    func testFindingsAndConfigurationAreBothOnThePage() {
        let screen = HealthScreen.of(.examined([Self.finding]), config: Self.groups)
        XCTAssertEqual(screen.verdict, .findings(1))
        XCTAssertEqual(screen.findings, [Self.finding])
        XCTAssertEqual(screen.configuration, Self.groups)
        XCTAssertFalse(screen.noMatches)
    }

    /// The verdict is the reading's and never the filter's. A word that hides
    /// every finding leaves the count as it was and says «no matches» under it;
    /// it is not a Mac with nothing wrong with it.
    func testAFilterHidesFindingsWithoutChangingTheVerdict() {
        let screen = HealthScreen.of(.examined([Self.finding, Self.second]),
                                     config: Self.groups, needle: "zzqqnope")
        XCTAssertEqual(screen.verdict, .findings(2))
        XCTAssertEqual(screen.findings, [])
        XCTAssertTrue(screen.noMatches)
        XCTAssertEqual(screen.configuration, [], "a group the needle matches nothing of stayed")
        // And a filter that hides nothing is the ordinary reading.
        XCTAssertFalse(HealthScreen.of(.examined([Self.finding]), config: [], needle: "deprecated").noMatches)
    }

    // MARK: - The only finding is open

    /// **One finding is drawn open and has no control to close it; two or more
    /// are closed until pressed.** `total` is the reading's own count, so a
    /// filter narrowing three to one does not make that one uncloseable.
    func testTheOnlyFindingIsAlwaysOpenAndTheOthersOpenWhenPressed() {
        XCTAssertTrue(HealthScreen.isOpen(Self.finding, of: 1, opened: []))
        XCTAssertFalse(HealthScreen.canToggle(total: 1), "the only finding has a control to close it")
        XCTAssertFalse(HealthScreen.isOpen(Self.finding, of: 2, opened: []))
        XCTAssertTrue(HealthScreen.isOpen(Self.finding, of: 2, opened: [Self.finding.id]))
        XCTAssertFalse(HealthScreen.isOpen(Self.second, of: 2, opened: [Self.finding.id]),
                       "opening one finding opened another")
        XCTAssertTrue(HealthScreen.canToggle(total: 2))
    }

    // MARK: - What the verdict says

    /// The four verdicts are four sentences in every language, and the two that
    /// have something to add have a second line the other two do not: a
    /// wait says what it waits for and no more, and a Mac nobody could examine
    /// says nothing about itself.
    func testTheVerdictsSayDifferentThingsInEveryLanguage() {
        AppLanguage.each { language in
            let verdicts: [HealthVerdict] = [.checking, .clean, .unexaminable, .findings(3)]
            let titles = verdicts.map(HomebrewHealthPage.verdictTitle)
            XCTAssertEqual(Set(titles).count, 4,
                           "\(language.rawValue): two readings share a sentence — \(titles)")
            XCTAssertFalse(titles.contains(where: \.isEmpty), "\(language.rawValue): \(titles)")

            XCTAssertNil(HomebrewHealthPage.verdictDetail(.checking), language.rawValue)
            XCTAssertNil(HomebrewHealthPage.verdictDetail(.unexaminable),
                         "\(language.rawValue): a Mac nobody could examine says something about itself")
            let clean = HomebrewHealthPage.verdictDetail(.clean)
            let findings = HomebrewHealthPage.verdictDetail(.findings(1))
            XCTAssertNotNil(clean, language.rawValue)
            XCTAssertNotNil(findings, language.rawValue)
            XCTAssertNotEqual(clean, findings, """
                \(language.rawValue): a Mac with findings and a clean one carry one second line
                """)
        }
    }

    /// The count is a number in the sentence, and it is the number given —
    /// a label with `\(count)` typed in the wrong slot of a translation is the
    /// defect an interpolated table can have and a `.strings` entry cannot.
    func testTheCountAppearsInTheFindingsSentenceInEveryLanguage() {
        AppLanguage.each { language in
            for count in [1, 2, 7, 12] {
                XCTAssertTrue(HbStr.findingsCount(count).contains(String(count)),
                              "\(language.rawValue): the count \(count) is missing from «\(HbStr.findingsCount(count))»")
            }
            XCTAssertNotEqual(HbStr.findingsCount(1), HbStr.findingsCount(2), language.rawValue)
        }
    }

    /// «Nothing to fix» is the one sentence that may claim a healthy Mac, and
    /// no other verdict may say it.
    func testOnlyACleanReadingSaysNothingToFix() {
        AppLanguage.each { language in
            for verdict: HealthVerdict in [.checking, .unexaminable, .findings(1)] {
                XCTAssertNotEqual(HomebrewHealthPage.verdictTitle(verdict), HbStr.nothingToFix,
                                  "\(language.rawValue): \(verdict) says «Nothing to fix.»")
            }
            XCTAssertEqual(HomebrewHealthPage.verdictTitle(.clean), HbStr.nothingToFix, language.rawValue)
        }
    }

    /// The two words VoiceOver reads after a title, and the word on the
    /// configuration card, are distinct and named.
    func testTheStateWordsAreDistinctAndTheCardIsNamedInEveryLanguage() {
        AppLanguage.each { language in
            XCTAssertNotEqual(HelmA11y.expanded(true), HelmA11y.expanded(false), language.rawValue)
            XCTAssertFalse(HelmA11y.expanded(true).isEmpty || HelmA11y.expanded(false).isEmpty, language.rawValue)
            XCTAssertFalse(HbStr.headingConfiguration.isEmpty, language.rawValue)
            XCTAssertNotEqual(HbStr.headingConfiguration, HbStr.segHealth,
                              "\(language.rawValue): a card repeats the segment's own word")
        }
    }

    /// The three group names are three names, and the keys beside them are
    /// Homebrew's and are never translated. The second half is the one worth
    /// pinning: a translated `CLT` or `HOMEBREW_PREFIX` names something the
    /// person cannot then look up anywhere.
    func testTheGroupNamesAreOursAndTheKeysAreHomebrewsInEveryLanguage() {
        AppLanguage.each { language in
            let names = ConfigSection.allCases.map(HbStr.configSectionName)
            XCTAssertEqual(Set(names).count, 3,
                           "\(language.rawValue): two groups share a name — \(names)")
            XCTAssertFalse(names.contains(where: \.isEmpty), "\(language.rawValue): \(names)")
            XCTAssertEqual(Self.lines.map(\.key),
                           ["HOMEBREW_VERSION", "CPU", "Clang", "HOMEBREW_PREFIX",
                            "macOS", "Xcode"],
                           "\(language.rawValue): a key was translated")
        }
    }

    // MARK: - The one line the closed configuration card says

    func testTheSummaryNamesThisHomebrewThisMacAndThisPrefix() {
        XCTAssertEqual(ConfigSummary.of(Self.lines),
                       "Homebrew 7.0.1 · macOS 27.0-arm64 · /opt/homebrew")
    }

    /// A fact `brew config` did not print is left out and not guessed, and a
    /// document with none of the three has no line at all.
    func testTheSummaryLeavesOutWhatBrewDidNotPrint() {
        XCTAssertEqual(ConfigSummary.of([ConfigLine(key: "macOS", value: "27.0-arm64", section: .machine)]),
                       "macOS 27.0-arm64")
        XCTAssertNil(ConfigSummary.of([ConfigLine(key: "CPU", value: "x", section: .machine)]))
        XCTAssertNil(ConfigSummary.of([]))
    }

    // MARK: - What reaches the page

    /// The reading reaches the page, groups and document both.
    func testTheReadingReachesThePage() async {
        let (hb, _, _) = model(issues: [], config: Self.config)
        await hb.refreshConfig()
        XCTAssertEqual(hb.configGroups, Self.groups)
        XCTAssertEqual(hb.config?.text, Self.document, """
            the document did not survive the wire — «Copy for a bug report» is the one thing \
            that reads it, and it is what a bug report asks for
            """)
    }

    /// **A refused `brew doctor` does not take the configuration with it.**
    func testARefusedDoctorLeavesTheConfigurationAlone() async {
        let (hb, _, bench) = model(issues: [Self.finding], config: Self.config)
        hb.segment = .health
        await hb.refreshConfig()
        await hb.refreshDoctor()
        XCTAssertEqual(hb.configGroups, Self.groups, "precondition: the configuration was read")

        bench.issues = nil
        await hb.refreshDoctor()
        XCTAssertEqual(hb.doctor, .refused, "precondition: the reading was refused")
        XCTAssertEqual(hb.configGroups, Self.groups, """
            a refused `brew doctor` took the configuration off the page — it says nothing about \
            `brew config` at all
            """)
    }

    /// A refused `brew config` keeps the last answer — the module's own rule
    /// for every list reply, and the opposite of what `refreshDoctor` does on
    /// purpose: a stale configuration is still a true thing about a machine
    /// that has not moved, where stale *findings* are a claim about a Mac that
    /// has just failed to be examined.
    func testARefusedConfigKeepsTheLastAnswer() async {
        let (hb, _, bench) = model(issues: [], config: Self.config)
        await hb.refreshConfig()
        XCTAssertEqual(hb.configGroups.count, 3, "precondition: the groups were read")

        bench.config = nil
        await hb.refreshConfig()
        XCTAssertEqual(hb.configGroups, Self.groups, """
            a refused reading replaced a configuration that had been read with nothing, so the \
            Configuration card vanished off a machine whose configuration is unchanged
            """)
    }

    // MARK: - The construction the fix gate depends on

    private static let page = "Sources/Modules/Homebrew/UI/HomebrewHealthPage.swift"

    private func code() throws -> String {
        SwiftSource.code(try RepoSource.text(of: Self.page))
    }

    private func typeBody(_ name: String) throws -> String {
        let code = try code()
        let characters = Array(code)
        let bodies = SwiftSource.typeBodies(in: code).filter { $0.name == name }
        guard bodies.count == 1, let found = bodies.first else {
            XCTFail("\(Self.page) declares \(bodies.count) types named \(name) where this reads one")
            return ""
        }
        return String(characters[(found.open + 1)..<found.close])
    }

    /// **The Run button asks; it never acts.** A press goes to `askToRunFix`,
    /// which is where `FixAsk` decides whether a question comes first and where
    /// the engine's second judgement is reached; nothing on this page may call
    /// `confirmFix` or send a fix itself, or a destructive command runs on a
    /// press with no question in front of it. The subject is asserted first: a
    /// page that stopped drawing a Run button at all would satisfy the absence.
    func testTheRunButtonAsksAndNeverActs() throws {
        let run = try typeBody("HealthRunButton")
        XCTAssertTrue(run.contains("hb.askToRunFix(fix)"), "the Run button no longer asks")
        XCTAssertTrue(run.contains("role: .destructive"), "the Run button lost its role")
        XCTAssertTrue(run.contains("helmDestructive()"), "the Run button lost the ink that shows it")
        XCTAssertTrue(run.contains(".disabled(hb.running)"), "the Run button is pressable while brew runs")
        let whole = try code()
        for forbidden in ["confirmFix", "runDoctorFix", ".doctorFix"] {
            XCTAssertFalse(whole.contains(forbidden),
                           "\(Self.page) reaches \(forbidden) — the press must go through the question")
        }
    }

    /// **One button per state.** The closed row's header draws Run when the fix
    /// is runnable and the row is closed; the open row's body draws it inside
    /// the fix block, beside the command — and the header does not, so the two
    /// are never on screen together.
    func testRunIsInTheHeaderOnlyWhileTheRowIsClosed() throws {
        let row = try typeBody("FindingRow")
        XCTAssertTrue(row.contains("if !open, let fix = issue.fix, fix.kind == .runnable {"), """
            the closed row's header no longer draws Run exactly when the row is closed and the \
            fix may be run, so a runnable fix is either unreachable or on screen twice
            """)
        XCTAssertTrue(row.contains("HealthFixBlock(hb: hb, fix: fix)"), "the open row draws no fix block")
        let block = try typeBody("HealthFixBlock")
        XCTAssertTrue(block.contains("if fix.kind == .runnable {"), "the fix block draws Run for a copy-only fix")
        XCTAssertTrue(block.contains("HbStr.brewNamedNoCommand"), "the fix block no longer says whose reading this is")
        XCTAssertTrue(block.contains("HbStr.helmReadsThisAs"), "the fix block lost the label naming Helm's reading")
    }

    /// **Brew's text is drawn as brew wrote it, and can be selected; the
    /// configuration is copied as brew printed it.** The body is `issue.body`
    /// with `textSelection`, and the button writes `BrewConfig.text` — not
    /// what the groups draw.
    func testBrewsWordsAreVerbatimAndTheConfigurationIsCopiedWhole() throws {
        let row = try typeBody("FindingRow")
        XCTAssertTrue(row.contains("Text(issue.body)"), "the finding's body is no longer drawn as it arrived")
        XCTAssertTrue(row.contains(".textSelection(.enabled)"), "the finding's body cannot be selected")
        let card = try typeBody("ConfigurationCard")
        XCTAssertTrue(card.contains("hb.config?.text"), "the copy no longer reads the document brew printed")
        XCTAssertTrue(card.contains("setString(text, forType: .string)"),
                      "the copy writes something other than the document")
        XCTAssertTrue(card.contains("HbStr.copyForABugReport"), "the card has lost its one action")
    }

    /// The reveal is the house's, on the house's curve — and the page owns no
    /// curve of its own (`MotionTokensAreTheOnlyCurvesTests` reads every file;
    /// this reads that both cards go through the modifier at all).
    func testBothCardsRevealThroughTheAccordion() throws {
        for name in ["FindingRow", "ConfigurationCard"] {
            let body = try typeBody(name)
            XCTAssertTrue(body.contains(".helmAccordion(open: open, height: $height)"),
                          "\(name) reveals by something other than the measured, clipped height")
        }
        let page = try typeBody("HomebrewHealthPage")
        XCTAssertEqual(page.components(separatedBy: "withAnimation(HelmMotion.disclosure)").count - 1, 2, """
            a press on a title is a transaction the accordion cannot see the cause of — the two \
            toggles carry `HelmMotion.disclosure` themselves, and a third spelling is a curve \
            nobody found
            """)
    }

    // MARK: - Mounted

    private func mounted(_ issues: [DoctorIssue]?, config: BrewConfig?,
                         query: String = "") async -> (HomebrewViewModel, MountedRender) {
        let (hb, mvm, _) = model(issues: issues, config: config)
        await hb.loadIfNeeded()
        hb.segment = .health
        await hb.refreshConfig()
        await hb.refreshDoctor()
        hb.query = query
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: 984, height: 700, appearance: .aqua)
        mount.settle(40)
        return (hb, mount)
    }

    /// The height of the page's scrolled content — what the cards add up to.
    private func contentHeight(_ mount: MountedRender) -> CGFloat? {
        mount.host.everyView(named: "HostingScrollView")
            .compactMap { ($0 as? NSScrollView)?.documentView?.frame.height }
            .max()
    }

    /// **A closed finding takes only its header, and the only finding is open
    /// and takes its body.** Three findings with long bodies, all closed, are
    /// three headers tall; one finding with the same body is a header and the
    /// body. If the accordion's measurement never lands the second reads as a
    /// closed row, and if closed rows keep their room the first reads taller
    /// than it should — this is the one reading of both.
    func testClosedFindingsTakeOnlyTheirHeadersAndTheOnlyFindingTakesItsBody() async throws {
        let long = (1...18).map { "  /usr/local/lib/libexample\($0).dylib" }.joined(separator: "\n")
        func finding(_ n: Int) -> DoctorIssue {
            DoctorIssue(severity: .caution, title: "Unbrewed dylibs were found (\(n)).",
                        body: "If you didn't put them there on purpose they could cause problems.\n\n"
                            + "Unexpected dylibs:\n" + long)
        }
        let (_, three) = await mounted([finding(1), finding(2), finding(3)], config: nil)
        let (_, one) = await mounted([finding(1)], config: nil)
        defer { three.drop(); one.drop() }

        let closed = try XCTUnwrap(contentHeight(three), "the page with three findings never mounted a scroll view")
        let open = try XCTUnwrap(contentHeight(one), "the page with one finding never mounted a scroll view")
        XCTAssertGreaterThan(open, closed + 100, """
            the one open finding is \(open) pt tall and three closed ones \(closed) — the body of \
            eighteen lines is either not drawn open, or is still taking its room when closed
            """)
    }

    /// Waiting and answered-clean and refused are three different drawings, and
    /// none of them is the page with findings: a verdict that is the same
    /// picture whatever the reading is a page that stopped saying anything.
    func testTheReadingsAreDrawnDifferently() async {
        let (_, clean) = await mounted([], config: Self.config)
        let (_, refused) = await mounted(nil, config: Self.config)
        let (_, found) = await mounted([Self.finding], config: Self.config)
        defer { clean.drop(); refused.drop(); found.drop() }

        let pictures = [clean.pixels(60...420), refused.pixels(60...420), found.pixels(60...420)]
        XCTAssertFalse(pictures.contains(where: { $0 == nil }), "a reading could not be photographed")
        XCTAssertEqual(Set(pictures.compactMap { $0 }).count, 3, """
            two of «clean», «refused» and «one finding» are drawn pixel for pixel the same
            """)
    }
}
