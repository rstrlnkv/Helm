import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The most expensive scan in the app, and what a sidebar click did to it.
///
/// Settings tears down a module's page on every visit, so a page-scoped
/// `@StateObject` is a new view model each time: the groups, the basket and the
/// phase all went with it, and hashing 14 580 files is minutes of work with no
/// on-disk cache behind it. Disk, Uninstaller, Homebrew, KeepAwake and Layout
/// all cache per host view model for exactly this reason.
///
/// Asserted on identity and on where a released answer lands — not on counts,
/// which a second scan would also satisfy.
@MainActor
final class SharedViewModelTests: XCTestCase {

    /// Two visits to the page, one view model.
    func testTheSameHostViewModelAlwaysGetsTheSameInstance() {
        let host = ModuleViewModel(transport: HeldTransport())

        let first = DuplicatesViewModel.shared(vm: host, store: duplicatesStore())
        let second = DuplicatesViewModel.shared(vm: host, store: duplicatesStore())

        XCTAssertTrue(first === second,
                      "a second visit to the page built a second view model, "
                      + "which is the search, the basket and the phase thrown away")
    }

    /// Switching the module off and on makes a new host view model, and the old
    /// transport's handler — held weakly by the engine — answers everything with
    /// empty Data from then on. Keyed to the host, not merely "exists".
    func testANewHostViewModelIsNotAnsweredByTheOldInstance() {
        let old = ModuleViewModel(transport: HeldTransport())
        let first = DuplicatesViewModel.shared(vm: old, store: duplicatesStore())

        let new = ModuleViewModel(transport: HeldTransport())
        let second = DuplicatesViewModel.shared(vm: new, store: duplicatesStore())

        XCTAssertFalse(first === second, "the page came back talking to a dead engine")
        XCTAssertTrue(second.vm === new, "the cached instance is not the one this page hosts")
    }

    /// The point of the cache: a search that was running when the page went away
    /// finishes into the instance the next page gets. This is why leaving the
    /// page does not cancel the engine — the work is still someone's.
    func testASearchRunningWhenThePageLeavesLandsInTheInstanceThePageComesBackTo() async {
        let transport = HeldTransport()
        let host = ModuleViewModel(transport: transport)
        var page: DuplicatesViewModel? = DuplicatesViewModel.shared(vm: host, store: duplicatesStore())
        page?.search()
        await untilParked(transport, count: 1)
        XCTAssertEqual(page?.phase, .searching)

        page = nil                                  // the sidebar click
        let returned = DuplicatesViewModel.shared(vm: host, store: duplicatesStore())
        transport.release(0, folder: "kept")
        for _ in 0..<200 { await Task.yield() }

        XCTAssertEqual(returned.phase, .result,
                       "the search that was running when the page closed answered nobody")
        XCTAssertEqual(returned.groups.flatMap { $0.paths }, ["/kept/a", "/kept/b"])
    }

    /// Switching the module off drops the cache: the tree behind a search of a
    /// large folder is nobody's once the module is gone.
    func testSwitchingTheModuleOffDropsTheCachedInstance() async {
        let host = ModuleViewModel(transport: HeldTransport())
        let first = DuplicatesViewModel.shared(vm: host, store: duplicatesStore())

        NotificationCenter.default.post(name: .helmModuleDisabled,
                                        object: DuplicatesDescriptor.id.rawValue)

        // The observer runs on the main queue, so the drop lands a turn later:
        // waited for as a condition, not as a fixed number of yields.
        var second = first
        for _ in 0..<1000 where second === first {
            await Task.yield()
            second = DuplicatesViewModel.shared(vm: host, store: duplicatesStore())
        }
        XCTAssertFalse(first === second,
                       "the module was switched off and its cached view model stayed reachable")
    }
}
