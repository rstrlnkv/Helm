import XCTest
import Foundation
import HelmContract
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The other two lists, and the one that must be left alone.**
///
/// `ASelectionDoesNotOutliveItsPackageTests` proves the rule for the installed
/// list. `reconcile` is called from three places — `refreshInstalled`,
/// `refreshOutdated` and `search` — and only the first of them had a guard, so
/// the two calls that arrive on the ordinary paths (an upgrade finishing, a
/// second search) were the two nothing could see. A selection that survives its
/// own row is an inspector describing a package that is gone, with a live
/// button on it.
///
/// The third test is the half the doc comment on `reconcile` claims and nothing
/// held: **one segment per call**. A reconcile that swept every segment against
/// whichever list had just arrived would pass both tests above and silently
/// throw away the selection a person left in the other two — the exact reason
/// the selection is per segment at all.
private final class ListsTransport: EngineTransport, @unchecked Sendable {
    private let stream = AsyncStream<EngineEvent>.makeStream()
    var events: AsyncStream<EngineEvent> { stream.stream }

    private let lock = NSLock()
    private var _installed: [BrewPackage] = []
    private var _outdated: [OutdatedPackage] = []
    private var _hits: [SearchHit] = []

    /// Set from the test between calls, which is what "the list moved under the
    /// selection" is: a terminal, an upgrade, a second search.
    var installed: [BrewPackage] {
        get { lock.lock(); defer { lock.unlock() }; return _installed }
        set { lock.lock(); _installed = newValue; lock.unlock() }
    }
    var outdated: [OutdatedPackage] {
        get { lock.lock(); defer { lock.unlock() }; return _outdated }
        set { lock.lock(); _outdated = newValue; lock.unlock() }
    }
    var hits: [SearchHit] {
        get { lock.lock(); defer { lock.unlock() }; return _hits }
        set { lock.lock(); _hits = newValue; lock.unlock() }
    }

    func send(_ command: EngineCommand) async throws -> Data {
        switch HomebrewCommand(rawValue: command.name) {
        case .listInstalled: return try JSONEncoder().encode(installed)
        case .outdated: return try JSONEncoder().encode(outdated)
        case .search: return try JSONEncoder().encode(hits)
        // Answered, and answered empty: the description batch runs behind every
        // list refresh, and a port that returns nothing there is a refusal the
        // view model logs rather than the ordinary "no descriptions yet".
        case .descriptions: return try JSONEncoder().encode([String: String]())
        default: return Data()
        }
    }
}

@MainActor
final class EverySegmentReconcilesItsOwnSelectionTests: XCTestCase {

    private let wget = BrewPackage(name: "wget", version: "1.25.0", isCask: false)
    private let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)
    private let node = OutdatedPackage(name: "node", installed: "26.8.2", latest: "26.9.0",
                                       isCask: false)
    private let git = OutdatedPackage(name: "git", installed: "2.54.0", latest: "2.55.0",
                                      isCask: false)
    private let helm = SearchHit(name: "helm", isCask: false)

    private func pair() -> (ListsTransport, HomebrewViewModel) {
        let transport = ListsTransport()
        return (transport, HomebrewViewModel(vm: ModuleViewModel(transport: transport)))
    }

    /// An upgrade finishes, `brew outdated` comes back without the package, and
    /// the inspector is still offering to upgrade it.
    func testTheUpdatesSegmentDropsASelectionItsListNoLongerHolds() async {
        let (transport, vm) = pair()
        transport.outdated = [node, git]
        vm.segment = .updates
        await vm.refreshOutdated()
        vm.select(node.id)
        XCTAssertEqual(vm.selected, node.id, "precondition: the selection was made")

        transport.outdated = [git]                       // node was upgraded
        await vm.refreshOutdated()
        XCTAssertNil(vm.selected, """
            the Updates inspector is still describing \(node.id), which `brew outdated` no \
            longer lists — with an Upgrade button that would act on it
            """)
    }

    /// The second search is the ordinary case: the person typed something else,
    /// and the hit they had open is not in the new answer. Read on Обновления —
    /// either package tab does, since the "Available to install" section
    /// replaced the Search segment 2026-09-24 and sits under both of them.
    ///
    /// `search(_:)` is called directly, the raw ask `AStaleSearchDoesNotLandOnANewerOneTests`
    /// already covers — `query` is set to match it *afterwards*, so
    /// `queryMoved()` finds `q == searchedQuery` and schedules no pause task
    /// of its own, which would otherwise race this test on a real clock.
    func testTheSectionDropsASelectionTheNewHitsDoNotHold() async {
        let (transport, vm) = pair()
        transport.hits = [helm, SearchHit(name: "helmfile", isCask: false)]
        vm.segment = .updates
        await vm.search("helm")
        vm.query = "helm"
        vm.select(helm.id)
        XCTAssertEqual(vm.selected, helm.id, "precondition: the selection was made")

        transport.hits = [SearchHit(name: "wget", isCask: false)]
        await vm.search("wget")
        vm.query = "wget"
        XCTAssertNil(vm.selected, """
            the inspector is still describing \(helm.id) after a search for something \
            else — with an Install button that would act on it
            """)
    }

    /// **One segment per call.** The two ids here are deliberately disjoint, so
    /// a reconcile that swept every segment against the installed list would
    /// clear both and this is the only test that could tell.
    func testARefreshReconcilesItsOwnSegmentAndLeavesTheOtherAlone() async {
        let (transport, vm) = pair()
        transport.installed = [wget, openssl]
        transport.outdated = [node]

        await vm.refreshInstalled()
        await vm.refreshOutdated()

        vm.segment = .installed; vm.select(openssl.id)
        vm.segment = .updates; vm.select(node.id)

        // Somebody uninstalls openssl@3 in a terminal and the installed list
        // comes back without it. Nothing happened to the outdated list.
        transport.installed = [wget]
        vm.segment = .installed
        await vm.refreshInstalled()

        XCTAssertNil(vm.selected, "the installed segment kept a package that is gone")
        vm.segment = .updates
        XCTAssertEqual(vm.selected, node.id, """
            refreshing the installed list threw away the Updates segment's selection, which \
            belongs to a list that did not move
            """)
    }

    /// **The section's own selection is a third list by the same rule**, now
    /// that it sits under the package tabs rather than being a segment of its
    /// own: a hit selected under Обновления must survive a refresh of
    /// Установленные, which shares nothing with it but the one query field.
    func testARefreshLeavesTheSectionsOwnSelectionAlone() async {
        let (transport, vm) = pair()
        transport.installed = [wget]
        transport.hits = [helm]

        await vm.refreshInstalled()
        vm.segment = .updates
        await vm.search("helm")
        vm.query = "helm"
        vm.select(helm.id)
        XCTAssertEqual(vm.selected, helm.id, "precondition: the selection was made")

        transport.installed = [wget, openssl]
        vm.segment = .installed
        await vm.refreshInstalled()

        vm.segment = .updates
        XCTAssertEqual(vm.selected, helm.id, """
            refreshing the installed list threw away the updates segment's own hit selection, \
            which belongs to a section that did not move
            """)
    }

    /// **The section's own selection must also survive refreshing *its own*
    /// segment.** `reconcile(_:against:)` used to check a hit's selection
    /// against only that segment's own list — `Set(answer.map(\.id))`, with
    /// no `shownHits` in it — so selecting a hit and then refreshing the very
    /// tab it is sitting under (an ordinary Refresh press, or the page's own
    /// `.onChange(of: segment)` on every arrival) reconciled the selection
    /// away before `reconcileVisible()` a line later ever got a chance to
    /// leave it alone.
    func testARefreshOfTheSectionsOwnSegmentLeavesItsSelectionAlone() async {
        let (transport, vm) = pair()
        transport.installed = [wget]
        transport.hits = [helm]

        await vm.refreshInstalled()
        vm.segment = .installed
        await vm.search("helm")
        vm.query = "helm"
        vm.select(helm.id)
        XCTAssertEqual(vm.selected, helm.id, "precondition: the selection was made")

        // The same tab's own list refreshes — wget again, nothing new.
        transport.installed = [wget]
        await vm.refreshInstalled()

        XCTAssertEqual(vm.selected, helm.id, """
            refreshing Установленные's own list threw away the section's selection sitting \
            under that very tab
            """)
    }

    /// **A word every hit for which is already on this Mac reads "No
    /// results.", not a heading with nothing under it.** `section` used to be
    /// computed off the raw `searchHits` rather than the already-excluded
    /// list `shownHits` draws — so `.answered` with `wget` the only hit, and
    /// `wget` already installed, answered `.found` while `shownHits` (which
    /// *does* exclude it) drew zero rows under the "Available to install"
    /// heading. Return on an installed package's own name is the ordinary way
    /// there — nothing stops brew from finding the very thing already on this
    /// Mac.
    func testAWordWhoseOnlyHitIsAlreadyInstalledReadsNothingFound() async {
        let (transport, vm) = pair()
        transport.installed = [wget]
        transport.hits = [SearchHit(name: wget.name, isCask: wget.isCask)]

        await vm.refreshInstalled()
        await vm.search("wget")
        vm.query = "wget"

        XCTAssertEqual(vm.section, .nothingFound, """
            \(String(describing: vm.section)) — the only hit for "wget" is the package \
            already installed, so the section has nothing left to offer
            """)
        XCTAssertEqual(vm.shownHits, [], "the installed hit must not be drawn under the heading")
    }

    /// The same defect the other way: installing the section's own hit must
    /// turn `.found` into `.nothingFound` the moment the Cellar is re-read,
    /// rather than leaving a stale `.found` reading over an emptied row list.
    func testInstallingTheSectionsOnlyHitTurnsFoundIntoNothingFound() async {
        let (transport, vm) = pair()
        transport.hits = [helm]

        await vm.refreshInstalled()
        await vm.search("helm")
        vm.query = "helm"
        XCTAssertEqual(vm.section, .found, "precondition: the hit is offered")

        // `helm` "installs" — the next `refreshInstalled` (what
        // `refreshAfterOp` runs after every operation) lists it.
        transport.installed = [BrewPackage(name: helm.name, version: "1.0.0", isCask: helm.isCask)]
        await vm.refreshInstalled()

        XCTAssertEqual(vm.section, .nothingFound, """
            \(String(describing: vm.section)) — the hit just installed is still read as \
            offered, over a heading with nothing left under it
            """)
    }

    /// **Состояние holds no selection at all.** Its findings open in place and
    /// its search section is not drawn (`HomebrewHealthPage`), so nothing on
    /// it can be selected and nothing selected there can be one of the ids the
    /// tab shows: `visibleIDs` is empty for it, and the next move of the field
    /// drops whatever was left there — a hit selected under Обновления and
    /// carried across by the picker's own binding is the way one could arrive.
    func testNothingStaysSelectedUnderTheHealthTab() async {
        let (transport, vm) = pair()
        transport.hits = [helm]
        vm.segment = .updates
        await vm.search("helm")
        vm.query = "helm"
        vm.select(helm.id)
        XCTAssertEqual(vm.selected, helm.id, "precondition: the selection was made")

        vm.segment = .health
        XCTAssertNil(vm.selected, "a selection was carried onto a tab that has nothing to select")
        vm.select(helm.id)
        vm.query = "helm "
        XCTAssertNil(vm.selected, """
            a selection made under Состояние survived a move of the field, which is where \
            `reconcileVisible` is asked what the tab can still show
            """)
    }

    /// The same defect, on Обновления.
    func testARefreshOfUpdatesLeavesItsOwnSectionSelectionAlone() async {
        let (transport, vm) = pair()
        transport.outdated = [node]
        transport.hits = [helm]

        vm.segment = .updates
        await vm.refreshOutdated()
        await vm.search("helm")
        vm.query = "helm"
        vm.select(helm.id)
        XCTAssertEqual(vm.selected, helm.id, "precondition: the selection was made")

        transport.outdated = [node]
        await vm.refreshOutdated()

        XCTAssertEqual(vm.selected, helm.id, """
            refreshing Обновления's own list threw away the section's selection sitting under \
            that very tab
            """)
    }
}
