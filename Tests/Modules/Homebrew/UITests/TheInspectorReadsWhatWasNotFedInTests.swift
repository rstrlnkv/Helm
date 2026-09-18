import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The inputs `InspectorStateTests` does not put in.**
///
/// That file proves the ordinary shape of every branch. These are the values
/// the branches were written against an assumption about: a `pinned` cask,
/// which the row comment calls impossible; a name that is a formula on this Mac
/// and a cask in the search results, which is the collision `BrewKey` exists
/// for and which `testLookupIsByIdAndNotByName` only pins on the *installed*
/// branch; and a package that is in `installed` and in `outdated` at once,
/// where the two segments must answer with two different actions about one id.
///
/// The rule under all four: `InspectorState.of` is the only thing that decides
/// what a button does, and every one of these inputs reaches it from a real
/// `brew`.
final class TheInspectorReadsWhatWasNotFedInTests: XCTestCase {

    private let node = BrewPackage(name: "node", version: "26.8.2", isCask: false)
    private let nodeOutdated = OutdatedPackage(name: "node", installed: "26.8.2",
                                               latest: "26.9.0", isCask: false)

    private func state(_ segment: HomebrewViewModel.Segment, _ selected: String?,
                       installed: [BrewPackage] = [], outdated: [OutdatedPackage] = [],
                       hits: [SearchHit] = [], issues: [DoctorIssue] = [],
                       loadedOutdated: Bool = true) -> InspectorState {
        InspectorState.of(segment: segment, selected: selected, installed: installed,
                          outdated: outdated, loadedOutdated: loadedOutdated,
                          hits: hits, issues: issues, config: [], descriptions: [:])
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
    /// type.** `pkgRow` and `InspectorState` both carry the comment «pinned and
    /// cask never overlap»; `BrewOutdatedParser` reads `pinned` out of the JSON
    /// for whichever array it is in, so the day a cask carries it the value
    /// arrives here. Refusing the upgrade is the safe answer either way — an
    /// `Upgrade` button that brew answers with «…is pinned» is a button that
    /// can only fail — so the judgement must be made on `pinned` alone and
    /// never on «it is a cask, so it cannot be pinned».
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
    /// *cask* in the results read as already here — the inspector would offer
    /// to uninstall an application this Mac has never had, and the row beside it
    /// would carry the «already installed» badge saying the same thing.
    func testACaskHitIsNotAlreadyInstalledBecauseItsFormulaIs() {
        let formula = BrewPackage(name: "docker", version: "1.0.0", isCask: false)
        let hit = SearchHit(name: "docker", isCask: true)
        guard let s = subject(state(.search, hit.id, installed: [formula], hits: [hit]),
                              "a cask hit whose formula is installed") else { return }
        XCTAssertTrue(s.isCask, "precondition: the subject is the cask hit")
        XCTAssertEqual(s.action, .install, """
            the cask `docker` is offered \(s.action) because the *formula* of that name is \
            installed — a name is not an identity here, which is what `BrewKey` exists for
            """)
        XCTAssertEqual(s.version, "", "the cask took the installed formula's version")
    }

    /// And the other way round, because a lookup by name is wrong in both
    /// directions and a guard that only tries one of them proves half of it.
    func testAFormulaHitIsNotAlreadyInstalledBecauseItsCaskIs() {
        let cask = BrewPackage(name: "docker", version: "2.0.0", isCask: true)
        let hit = SearchHit(name: "docker", isCask: false)
        guard let s = subject(state(.search, hit.id, installed: [cask], hits: [hit]),
                              "a formula hit whose cask is installed") else { return }
        XCTAssertFalse(s.isCask, "precondition: the subject is the formula hit")
        XCTAssertEqual(s.action, .install, """
            the formula `docker` is offered \(s.action) because the *cask* of that name is \
            installed
            """)
        XCTAssertEqual(s.version, "", "the formula took the installed cask's version")
    }

    // MARK: - One id, two segments

    /// A package that is installed *and* outdated is in two lists at once, and
    /// the id is the same string in both. Which segment is open decides what the
    /// button does — Uninstall under Установленные, Upgrade under Обновления —
    /// and the update itself is still named on the installed side, because the
    /// row's dot and the inspector read one fact.
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
    /// ordinary answer: the last package upgraded, a search for a word brew
    /// knows nothing about. The selection is reconciled away by the view model,
    /// but the state function is asked before and after that and must never
    /// fall back to whatever row happens to be first.
    ///
    /// **`.nothingToSelect` and not `.nothingSelected`**: a list that emptied
    /// has nothing to offer, and the invitation the second case draws is an
    /// instruction nobody can follow — `AnInvitationNeedsSomethingToChooseTests`
    /// is where that distinction lives. What this file is about is unchanged:
    /// the lookup must not fall back to whatever row happens to be first, and
    /// neither answer is a row.
    func testASelectionIntoAnEmptiedListIsNothingSelectedInEverySegment() {
        XCTAssertEqual(state(.installed, node.id, installed: []), .nothingToSelect)
        XCTAssertEqual(state(.updates, nodeOutdated.id, outdated: []), .nothingToSelect)
        XCTAssertEqual(state(.search, "f:helm", hits: []), .nothingToSelect)
    }

    /// The same three, asked for an id that a *different* segment's list holds —
    /// the shape a selection standing across a segment switch would take if the
    /// three lists shared one.
    func testASelectionFromAnotherSegmentsListIsNothingSelected() {
        let hit = SearchHit(name: "helm", isCask: false)
        XCTAssertEqual(state(.installed, hit.id, installed: [node], hits: [hit]), .nothingSelected)
        XCTAssertEqual(state(.updates, node.id, installed: [node], outdated: [nodeOutdated],
                             hits: [hit]) == .nothingSelected, false,
                       "precondition: node really is in the outdated list")
        XCTAssertEqual(state(.updates, hit.id, outdated: [nodeOutdated], hits: [hit]),
                       .nothingSelected)
        XCTAssertEqual(state(.search, node.id, installed: [node], hits: [hit]), .nothingSelected)
    }
}
