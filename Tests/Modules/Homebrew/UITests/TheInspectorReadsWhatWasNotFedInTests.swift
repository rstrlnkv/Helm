import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The inputs `InspectorStateTests.swift` does not put in.**
///
/// That file proves the ordinary shape of every branch. These are the values a
/// branch could assume away: a `pinned` cask; a name that is a formula on this
/// Mac and a cask in the search results (the collision `BrewKey` exists for);
/// a package in `installed` and in `outdated` at once; and a list that emptied.
/// `InspectorState.of` alone decides what a button does, and every one of these
/// inputs reaches it from a real `brew`.
final class TheInspectorReadsWhatWasNotFedInTests: XCTestCase {

    private let node = BrewPackage(name: "node", version: "26.8.2", isCask: false)
    private let nodeOutdated = OutdatedPackage(name: "node", installed: "26.8.2",
                                               latest: "26.9.0", isCask: false)

    private func state(_ segment: HomebrewViewModel.Segment, _ selected: String?,
                       installed: [BrewPackage] = [], outdated: [OutdatedPackage] = [],
                       hits: [SearchHit] = []) -> InspectorState {
        InspectorState.of(segment: segment, selected: selected, installed: installed,
                          outdated: outdated, loadedOutdated: true,
                          hits: hits, descriptions: [:])
    }

    private func subject(_ state: InspectorState, _ what: String,
                         file: StaticString = #filePath, line: UInt = #line) -> InspectorSubject? {
        guard case let .package(subject) = state else {
            XCTFail("\(what): the inspector said nothing is selected", file: file, line: line)
            return nil
        }
        return subject
    }

    // MARK: - A pinned cask

    /// **`brew pin` being formulae-only is a fact about brew, not about this
    /// type.** `BrewOutdatedParser` reads `pinned` for whichever array it is in,
    /// and an `Upgrade` button brew answers with «…is pinned» can only fail, so
    /// the refusal is made on `pinned` alone, never on «it is a cask».
    func testAPinnedCaskIsRefusedTheUpgradeToo() {
        let cask = OutdatedPackage(name: "figma", installed: "124.0", latest: "125.0",
                                   isCask: true, pinned: true)
        guard let s = subject(state(.updates, cask.id, outdated: [cask]), "a pinned cask") else { return }
        XCTAssertTrue(s.isCask, "precondition: the subject is the cask")
        XCTAssertEqual(s.action, .pinned, """
            a pinned cask is offered Upgrade, which `brew upgrade` answers with «…is pinned» — \
            the judgement was made on the kind and not on the pin
            """)
    }

    // MARK: - The collision, on the search branch

    /// `docker` is a formula and a cask. The installed formula must not make the
    /// *cask* under the section read as already here, or the inspector offers to
    /// uninstall an application this Mac never had. Any tab does: a hit is
    /// `HomebrewViewModel.shownHits` on each, and `PackageStanding.notInstalled`
    /// is the one place that excludes by id.
    func testACaskHitIsNotAlreadyInstalledBecauseItsFormulaIs() {
        let formula = BrewPackage(name: "docker", version: "1.0.0", isCask: false)
        let hit = SearchHit(name: "docker", isCask: true)
        guard let s = subject(state(.installed, hit.id, installed: [formula], hits: [hit]),
                              "a cask hit whose formula is installed") else { return }
        XCTAssertTrue(s.isCask, "precondition: the subject is the cask hit")
        XCTAssertEqual(s.action, .install, """
            the cask `docker` is offered \(s.action) because the *formula* of that name is \
            installed — a name is not an identity here, which is what `BrewKey` exists for
            """)
        XCTAssertEqual(s.version, "", "the cask took the installed formula's version")
    }

    /// And the other way round: a lookup by name is wrong in both directions.
    func testAFormulaHitIsNotAlreadyInstalledBecauseItsCaskIs() {
        let cask = BrewPackage(name: "docker", version: "2.0.0", isCask: true)
        let hit = SearchHit(name: "docker", isCask: false)
        guard let s = subject(state(.installed, hit.id, installed: [cask], hits: [hit]),
                              "a formula hit whose cask is installed") else { return }
        XCTAssertFalse(s.isCask, "precondition: the subject is the formula hit")
        XCTAssertEqual(s.action, .install, """
            the formula `docker` is offered \(s.action) because the *cask* of that name is \
            installed
            """)
        XCTAssertEqual(s.version, "", "the formula took the installed cask's version")
    }

    // MARK: - One id, two segments

    /// A package installed *and* outdated is in two lists under one id. The open
    /// segment decides the button (Uninstall under Установленные, Upgrade under
    /// Обновления), and the update is still named on the installed side, because
    /// the row's dot and the inspector read one fact.
    func testOneIdInTwoListsAnswersWithTheSegmentsOwnAction() {
        guard let onInstalled = subject(state(.installed, node.id, installed: [node],
                                              outdated: [nodeOutdated]), "installed"),
              let onUpdates = subject(state(.updates, node.id, installed: [node],
                                            outdated: [nodeOutdated]), "updates")
        else { return }

        XCTAssertEqual(onInstalled.action, .uninstall, """
            the Установленные inspector offers \(onInstalled.action) for a package that is also \
            outdated — the segment decides the action, and an upgrade reached from a list of \
            installed packages is the Обновления tab's door
            """)
        XCTAssertEqual(onInstalled.updates, .available("26.9.0"),
                       "the installed side lost the update the row's dot draws")
        XCTAssertEqual(onInstalled.version, "26.8.2",
                       "the installed side is showing the outdated line's two versions")
        XCTAssertEqual(onUpdates.action, .upgrade)
        XCTAssertEqual(onUpdates.version, "26.8.2 → 26.9.0")
    }

    // MARK: - A list that emptied rather than changed

    /// The three lists are replaced wholesale, and «replaced with nothing» is an
    /// ordinary answer. The state function is asked before and after the view
    /// model reconciles the selection, and never falls back to whatever row is
    /// first. It answers `.nothingToSelect`, not `.nothingSelected`: the
    /// invitation the second draws is an instruction nobody can follow.
    func testASelectionIntoAnEmptiedListIsNothingSelectedInEverySegment() {
        XCTAssertEqual(state(.installed, node.id, installed: []), .nothingToSelect)
        XCTAssertEqual(state(.updates, nodeOutdated.id, outdated: []), .nothingToSelect)
        // Состояние has no inspector, so an id it once could have held is
        // nothing there either.
        XCTAssertEqual(state(.health, "f:helm", hits: []), .nothingToSelect)
    }

    /// The same, asked for an id that a *different* list holds: a selection
    /// standing across a segment switch. `hits` is left out on purpose: it is
    /// shared by both package tabs, so a hit resolving under another segment is
    /// the feature (`testAHitUnderTheSectionOffersInstallationOnUpdatesToo`).
    func testASelectionFromAnotherSegmentsListIsNothingSelected() {
        // `node`'s id, asked of Установленные without `node` in its own
        // `installed` list — only `outdated` names it here.
        XCTAssertEqual(state(.installed, node.id, outdated: [nodeOutdated]), .nothingToSelect)
        XCTAssertEqual(state(.updates, node.id, installed: [node], outdated: [nodeOutdated])
                       == .nothingSelected, false,
                       "precondition: node really is in the outdated list")
        // `nodeOutdated`'s id, asked of Обновления with `outdated` empty —
        // only `installed` names the package here.
        XCTAssertEqual(state(.updates, nodeOutdated.id, installed: [node]), .nothingToSelect)
    }
}
