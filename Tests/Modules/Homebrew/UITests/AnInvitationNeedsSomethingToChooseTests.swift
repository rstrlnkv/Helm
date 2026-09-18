import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **«Select a package» over a list with nothing in it.**
///
/// The inspector's empty sentence is an instruction, and an instruction is only
/// honest while it can be followed. Measured 2026-09-16 on the 984 pt pane the
/// app opens: 515 pt of the 984 — 52 % of it — invited a choice out of a master
/// that was drawing «Homebrew did not answer, so nothing is known about the
/// installed packages right now.» At its worst, on a Состояние whose findings
/// *and* configuration both refused, the pane held one unselectable sentence on
/// the left and an invitation on the right.
///
/// **One case for all three readings.** Waiting, answered-empty and refused are
/// three different sentences in the *list* — that is `ListScreen`'s job and
/// `ARefusedListIsNotAnEmptyOneTests` holds it — and the same answer in the
/// inspector, because what makes the invitation wrong is that there is nothing
/// to choose, not why. The list's sentence is the page's one account of the
/// reason; a second one here would be the defect this page keeps being repaired
/// of.
///
/// **And it must not have swallowed the invitation.** A pane that never invites
/// anything passes «the invitation is gone» at every width and in every state,
/// so every case below asserts the invitation is still drawn where there *is*
/// something to choose.
@MainActor
final class AnInvitationNeedsSomethingToChooseTests: XCTestCase {

    nonisolated(unsafe) static let wget = BrewPackage(name: "wget", version: "1.25.0",
                                                      isCask: false)
    private static let outdated = OutdatedPackage(name: "wget", installed: "1.24.0",
                                                 latest: "1.25.0", isCask: false)
    private static let hit = SearchHit(name: "wget", isCask: false)
    private static let issue = DoctorIssue(severity: .caution, title: "Unbrewed header files",
                                           body: "…", fix: nil)
    private static let group = ConfigGroup(section: .brew,
                                           lines: [ConfigLine(key: "HOMEBREW_VERSION",
                                                              value: "7.0.1", section: .brew)])

    private func state(segment: HomebrewViewModel.Segment,
                       selected: String?,
                       installed: [BrewPackage] = [],
                       outdated: [OutdatedPackage] = [],
                       hits: [SearchHit] = [],
                       issues: [DoctorIssue] = [],
                       config: [ConfigGroup] = []) -> InspectorState {
        InspectorState.of(segment: segment, selected: selected, installed: installed,
                          outdated: outdated, loadedOutdated: true, hits: hits, issues: issues,
                          config: config, descriptions: [:])
    }

    /// **The claim, one segment at a time.** An empty list answers
    /// `.nothingToSelect` whatever the selection says, and a list with a row in
    /// it answers `.nothingSelected` — the invitation — while nothing is
    /// picked.
    func testAnEmptyListIsNeverAnInvitation() {
        XCTAssertEqual(state(segment: .installed, selected: nil), .nothingToSelect)
        XCTAssertEqual(state(segment: .installed, selected: nil, installed: [Self.wget]),
                       .nothingSelected, """
            a list with a row in it and nothing picked no longer invites a choice — the \
            sentence has been removed rather than made honest
            """)

        XCTAssertEqual(state(segment: .updates, selected: nil), .nothingToSelect)
        XCTAssertEqual(state(segment: .updates, selected: nil, outdated: [Self.outdated]),
                       .nothingSelected)

        XCTAssertEqual(state(segment: .search, selected: nil), .nothingToSelect)
        XCTAssertEqual(state(segment: .search, selected: nil, hits: [Self.hit]),
                       .nothingSelected)

        // Состояние counts both of its lists. `brew doctor` refusing still
        // leaves `brew config`'s groups on screen, and those rows *are*
        // selectable — so only the pane with neither is the empty one.
        XCTAssertEqual(state(segment: .health, selected: nil), .nothingToSelect)
        XCTAssertEqual(state(segment: .health, selected: nil, issues: [Self.issue]),
                       .nothingSelected)
        XCTAssertEqual(state(segment: .health, selected: nil, config: [Self.group]),
                       .nothingSelected, """
            a refused `brew doctor` with a configuration beside it draws no invitation, where \
            the configuration's own rows are there to be chosen
            """)
    }

    /// **A selection that outlived its list is not a reason to go on
    /// inviting.** The id is one no list holds, which before this was read as
    /// "nothing is selected" and drew the instruction over an empty pane.
    func testASelectionLeftOverFromAnEmptiedListIsNotAnInvitationEither() {
        XCTAssertEqual(state(segment: .installed, selected: Self.wget.id), .nothingToSelect)
        XCTAssertEqual(state(segment: .updates, selected: Self.outdated.id), .nothingToSelect)
        XCTAssertEqual(state(segment: .search, selected: Self.hit.id), .nothingToSelect)
        XCTAssertEqual(state(segment: .health, selected: Self.issue.id), .nothingToSelect)

        // And a selection no *populated* list holds is still the invitation:
        // there are rows, one of them can be picked, and this one is stale.
        XCTAssertEqual(state(segment: .installed, selected: "f:gone", installed: [Self.wget]),
                       .nothingSelected)
    }

    /// **And on the real page the half-pane goes quiet.**
    ///
    /// The decision above is a value; this is the drawing. Three readings of one
    /// segment — waiting, answered-empty, refused — must each leave the
    /// inspector with nothing in it, and the same page with a row in the list
    /// must put the sentence back. Without that last half the claim passes over
    /// a page whose inspector draws nothing ever.
    ///
    /// The reading is of the inspector's own half of the pane — right of the
    /// divider, and
    /// the vertical middle where `HelmEmptyState` centres its sentence. 480 pt
    /// and not the divider's own 456: `masterWidth` gives the master 444 pt of a
    /// 984 pt pane, and a reading that starts on the divider is a reading of the
    /// divider. There is no view to read it off: the sentence is SwiftUI drawing straight into
    /// the host, with no AppKit view of its own, which is why `RenderedInk`
    /// takes a column range.
    func testTheInspectorsHalfOfThePaneIsEmptyWhenTheListIs() async {
        // Named light: this Mac switches appearance by the sun, and an unnamed
        // reading is a reading of the hour.
        func inkOfTheInspector(_ vm: ModuleViewModel) -> Int? {
            let mount = MountedRender(HomebrewSettingsPage(vm: vm),
                                      width: 984, height: 748, appearance: .aqua)
            mount.settle(30)
            let ink = RenderedInk.read(mount.host, points: 250...500, columns: 480...960)
            mount.drop()
            return ink
        }

        let refused = ModuleViewModel(transport: ListRefuses())
        let refusedModel = HomebrewViewModel.shared(vm: refused)
        await refusedModel.loadIfNeeded()
        XCTAssertTrue(refusedModel.status.installed,
                      "precondition: the page draws its manager rather than the install screen")
        XCTAssertEqual(refusedModel.installedReading, .unanswerable,
                       "precondition: the list refused with nothing behind it")
        let quiet = inkOfTheInspector(refused)
        XCTAssertNotNil(quiet, "the inspector's column could not be read, so nothing below is")

        let full = ModuleViewModel(transport: OnePackage())
        let fullModel = HomebrewViewModel.shared(vm: full)
        await fullModel.loadIfNeeded()
        XCTAssertTrue(fullModel.status.installed, "precondition: the manager is what draws")
        XCTAssertEqual(fullModel.installed.count, 1, "precondition: the list has a row in it")
        let inviting = inkOfTheInspector(full)
        XCTAssertNotNil(inviting)

        guard let quiet, let inviting else { return }
        XCTAssertGreaterThan(inviting, 0, """
            the inspector draws nothing even with a package to choose — the sentence has been \
            deleted rather than made conditional, and the reading below is of a column that is \
            always blank
            """)
        XCTAssertLessThan(quiet, inviting / 4, """
            the inspector drew \(quiet) of ink beside a refused list against \(inviting) beside \
            a list with a row in it — it is still inviting a choice that cannot be made
            """)
    }

    private final class ListRefuses: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return Data()
            default: return Data("[]".utf8)
            }
        }
    }

    private final class OnePackage: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode(
                    [AnInvitationNeedsSomethingToChooseTests.wget])
            default: return Data("[]".utf8)
            }
        }
    }
}
