import XCTest
import Foundation
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **One list, two kinds of thing, and neither half may swallow the other.**
///
/// The health segment held `brew doctor`'s findings alone: an empty reading was
/// an empty pane, and the whole of the design was which of three sentences
/// stood in it. It holds `brew config`'s groups as well now, and that puts two
/// new ways to lose something in reach:
///
/// - the configuration swallowing the sentence — «Homebrew did not answer» is
///   the line a person decides whether to trust their Mac on, and a list with
///   rows on it has nowhere to draw a centred empty state;
/// - the findings swallowing the configuration — the reconcile that drops a
///   selection knew only the findings, so a refused `brew doctor`, which says
///   nothing whatever about `brew config`, threw away the group the person was
///   reading.
@MainActor
final class TheHealthListHoldsTwoKindsOfThingTests: XCTestCase {

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
        -> (HomebrewViewModel, Bench) {
        let bench = Bench(issues: issues, config: config)
        // `.shared`, for the reason `ARefusedDoctorIsNotAHealthyMacTests` gives:
        // the page reaches the cache, so a view model built beside it is one
        // the page never reads.
        return (HomebrewViewModel.shared(vm: ModuleViewModel(transport: bench)), bench)
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

    /// Ids are distinct across the two kinds of row, which is what lets one
    /// selection stand for both. A `DoctorIssue`'s id is built from its own
    /// text; a group's is `cfg:` and a case name.
    func testAGroupsIdCannotCollideWithAFindingsOrAPackagesID() {
        let ids = Set(Self.groups.map(\.id))
        XCTAssertEqual(ids.count, 3)
        XCTAssertFalse(ids.contains(Self.finding.id))
        XCTAssertFalse(ids.contains(BrewKey.of(name: "brew", isCask: false)))
    }

    // MARK: - What the screen is

    /// With nothing but `brew doctor`'s reading, the segment is still the one
    /// centred sentence it was — all three of them, each its own.
    func testWithNoConfigurationTheScreenIsStillOneSentence() {
        XCTAssertEqual(HealthScreen.of(.notAsked, config: []), .sentence(.busy))
        XCTAssertEqual(HealthScreen.of(.examined([]), config: []), .sentence(.clean))
        XCTAssertEqual(HealthScreen.of(.refused, config: []), .sentence(.unexaminable))
    }

    /// **The one assertion this file exists for.** A `brew doctor` that could
    /// not be asked still leaves a configuration that could, and the sentence
    /// saying why there are no findings has to survive beside it. Collapsing
    /// either way loses something a person needs: the sentence, or every row
    /// that was read successfully.
    func testARefusedDoctorKeepsBothItsSentenceAndTheConfiguration() {
        let screen = HealthScreen.of(.refused, config: Self.groups)
        guard case let .groups(checkup, configuration) = screen else {
            return XCTFail("the configuration was thrown away with the findings: \(screen)")
        }
        XCTAssertEqual(checkup, [.note(.unexaminable)], """
            the sentence explaining why there are no findings did not survive the configuration \
            being on the list — «Nothing is known about this Mac» is the line a person decides \
            whether to trust the app on
            """)
        XCTAssertEqual(configuration, Self.groups)
    }

    /// And the same for the two readings that are not a refusal, so the rule is
    /// about the shape rather than about one arm of it.
    func testEveryDoctorReadingKeepsItsSentenceBesideTheConfiguration() {
        for (reading, note) in [(DoctorReading.notAsked, HealthNote.busy),
                                (.examined([]), .clean),
                                (.refused, .unexaminable)] {
            XCTAssertEqual(HealthScreen.of(reading, config: Self.groups),
                           .groups(checkup: [.note(note)], configuration: Self.groups),
                           "the \(note.rawValue) reading lost its sentence or its configuration")
        }
    }

    /// Findings and configuration on one list, each under its own heading.
    func testFindingsAndConfigurationAreBothOnTheList() {
        XCTAssertEqual(HealthScreen.of(.examined([Self.finding]), config: Self.groups),
                       .groups(checkup: [.issue(Self.finding)], configuration: Self.groups))
    }

    /// The three sentences are three sentences, in all eight languages — two
    /// readings drawn with one string would satisfy every structural assertion
    /// above and still say the same thing to the person.
    func testTheThreeNotesSayThreeThingsInEveryLanguage() {
        AppLanguage.each { language in
            let said = [HealthNote.busy, .clean, .unexaminable]
                .map(HomebrewSettingsPage.healthNote)
            XCTAssertEqual(Set(said).count, 3,
                           "\(language.rawValue): two readings share a sentence — \(said)")
            XCTAssertFalse(said.contains(where: \.isEmpty), "\(language.rawValue): \(said)")
        }
    }

    /// The two headings are named, distinct, and not the segment's own word
    /// repeated — a heading that says what the tab above it says is a heading
    /// carrying nothing.
    func testTheTwoHeadingsAreNamedAndDistinctInEveryLanguage() {
        AppLanguage.each { language in
            let words = [HbStr.headingCheckup, HbStr.headingConfiguration]
            XCTAssertEqual(Set(words).count, 2, "\(language.rawValue): one word for both headings")
            XCTAssertFalse(words.contains(where: \.isEmpty), "\(language.rawValue): \(words)")
            XCTAssertFalse(words.contains(HbStr.segHealth),
                           "\(language.rawValue): a heading repeats the segment's own word")
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

    // MARK: - What the inspector describes

    /// Selecting a group describes that group; selecting a finding still
    /// describes the finding; selecting neither describes nothing.
    func testTheInspectorDescribesWhicheverKindIsSelected() {
        func state(_ selected: String?) -> InspectorState {
            InspectorState.of(segment: .health, selected: selected, installed: [], outdated: [],
                              loadedOutdated: true, hits: [], issues: [Self.finding],
                              config: Self.groups, descriptions: [:])
        }
        guard case let .configSection(group) = state(Self.groups[1].id) else {
            return XCTFail("a selected configuration group described nothing")
        }
        XCTAssertEqual(group, Self.groups[1])
        XCTAssertEqual(state(Self.finding.id), .issue(Self.finding))
        XCTAssertEqual(state("cfg:nothing"), .nothingSelected)
        XCTAssertEqual(state(nil), .nothingSelected)
    }

    /// The empty sentence covers both kinds. It said «Select a finding» while
    /// findings were all this list held, which is a sentence that is wrong
    /// whenever somebody is looking at the other half of the list.
    func testTheEmptySentenceNamesMoreThanFindingsInEveryLanguage() {
        AppLanguage.each { language in
            XCTAssertNotEqual(HbStr.selectAFindingOrASection, HbStr.nothingSelected,
                              "\(language.rawValue): the package sentence over a list of findings")
            XCTAssertFalse(HbStr.selectAFindingOrASection.isEmpty, language.rawValue)
        }
    }

    // MARK: - The query, and what it does to the selection

    /// The reading reaches the page, groups and document both.
    func testTheReadingReachesThePage() async {
        let (hb, _) = model(issues: [], config: Self.config)
        await hb.refreshConfig()
        XCTAssertEqual(hb.configGroups, Self.groups)
        XCTAssertEqual(hb.config?.text, Self.document, """
            the document did not survive the wire — «Copy for a bug report» is the one thing \
            that reads it, and it is what a bug report asks for
            """)
    }

    /// **A refused `brew doctor` does not take the configuration's selection
    /// with it.** The reconcile that drops a stale selection took the findings
    /// alone, and this list holds two kinds of thing: reading a group and
    /// pressing Refresh on a Mac whose `brew doctor` is slow or gone threw away
    /// what was on screen for a reason that had nothing to do with it.
    func testARefusedDoctorLeavesASelectedConfigurationGroupAlone() async {
        let (hb, bench) = model(issues: [Self.finding], config: Self.config)
        hb.segment = .health
        await hb.refreshConfig()
        await hb.refreshDoctor()
        hb.select(Self.groups[0].id)
        XCTAssertEqual(hb.selected, Self.groups[0].id, "precondition: the group was selected")

        bench.issues = nil
        await hb.refreshDoctor()
        XCTAssertEqual(hb.doctor, .refused, "precondition: the reading was refused")
        XCTAssertEqual(hb.selected, Self.groups[0].id, """
            a refused `brew doctor` deselected the configuration group being read — the reconcile \
            swept the whole list against the findings alone
            """)
    }

    /// And the reverse: a finding's selection still goes when the finding does,
    /// which is the rule the reconcile exists for and which the fix above must
    /// not have loosened.
    func testARefusedDoctorStillDropsASelectedFinding() async {
        let (hb, bench) = model(issues: [Self.finding], config: Self.config)
        hb.segment = .health
        await hb.refreshConfig()
        await hb.refreshDoctor()
        hb.select(Self.finding.id)
        XCTAssertEqual(hb.selected, Self.finding.id, "precondition: the finding was selected")

        bench.issues = nil
        await hb.refreshDoctor()
        XCTAssertNil(hb.selected, "the inspector still describes a finding nothing answered for")
    }

    /// A refused `brew config` keeps the last answer — the module's own rule
    /// for every list reply, and the opposite of what `refreshDoctor` does on
    /// purpose: a stale configuration is still a true thing about a machine
    /// that has not moved, where stale *findings* are a claim about a Mac that
    /// has just failed to be examined.
    func testARefusedConfigKeepsTheLastAnswer() async {
        let (hb, bench) = model(issues: [], config: Self.config)
        await hb.refreshConfig()
        XCTAssertEqual(hb.configGroups.count, 3, "precondition: the groups were read")

        bench.config = nil
        await hb.refreshConfig()
        XCTAssertEqual(hb.configGroups, Self.groups, """
            a refused reading replaced a configuration that had been read with nothing, so the \
            Configuration heading vanished off a machine whose configuration is unchanged
            """)
    }
}
