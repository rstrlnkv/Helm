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
    /// and the hit they had open is not in the new answer.
    func testTheSearchSegmentDropsASelectionTheNewHitsDoNotHold() async {
        let (transport, vm) = pair()
        transport.hits = [helm, SearchHit(name: "helmfile", isCask: false)]
        vm.segment = .search
        await vm.search("helm")
        vm.select(helm.id)
        XCTAssertEqual(vm.selected, helm.id, "precondition: the selection was made")

        transport.hits = [SearchHit(name: "wget", isCask: false)]
        await vm.search("wget")
        XCTAssertNil(vm.selected, """
            the search inspector is still describing \(helm.id) after a search for something \
            else — with an Install button that would act on it
            """)
    }

    /// **One segment per call.** The three ids here are deliberately disjoint,
    /// so a reconcile that swept every segment against the installed list would
    /// clear all three and this is the only test that could tell.
    func testARefreshReconcilesItsOwnSegmentAndLeavesTheOthersAlone() async {
        let (transport, vm) = pair()
        transport.installed = [wget, openssl]
        transport.outdated = [node]
        transport.hits = [helm]

        await vm.refreshInstalled()
        await vm.refreshOutdated()
        vm.segment = .search
        await vm.search("helm")

        vm.segment = .installed; vm.select(openssl.id)
        vm.segment = .updates; vm.select(node.id)
        vm.segment = .search; vm.select(helm.id)

        // Somebody uninstalls openssl@3 in a terminal and the installed list
        // comes back without it. Nothing happened to the other two lists.
        transport.installed = [wget]
        vm.segment = .installed
        await vm.refreshInstalled()

        XCTAssertNil(vm.selected, "the installed segment kept a package that is gone")
        vm.segment = .updates
        XCTAssertEqual(vm.selected, node.id, """
            refreshing the installed list threw away the Updates segment's selection, which \
            belongs to a list that did not move
            """)
        vm.segment = .search
        XCTAssertEqual(vm.selected, helm.id, """
            refreshing the installed list threw away the search segment's selection, which \
            belongs to a list that did not move
            """)
    }
}
