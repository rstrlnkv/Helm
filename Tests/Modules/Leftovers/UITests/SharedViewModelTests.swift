import XCTest
import HelmContract
import HelmUI
@testable import Module_Leftovers_UI

/// A sidebar click used to throw away the scan and every checkbox with it.
///
/// Settings rebuilds a module's page on every visit, so a page-scoped
/// `@StateObject` is a new view model each time: the list, the ticks, the
/// filter. Disk, Uninstaller, Homebrew, KeepAwake and Layout all cache per host
/// view model for exactly this reason.
@MainActor
final class SharedViewModelTests: XCTestCase {

    private final class SilentTransport: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    func testTheSameHostViewModelAlwaysGetsTheSameInstance() {
        let host = ModuleViewModel(transport: SilentTransport())

        let first = LeftoversViewModel.shared(vm: host)
        let second = LeftoversViewModel.shared(vm: host)

        XCTAssertTrue(first === second,
                      "a second visit to the page built a second view model, "
                      + "which is the scan and every checkbox thrown away")
    }

    /// The ticks are the state worth keeping: they are a decision about
    /// load-bearing files that nothing in this module pre-makes.
    func testTheSelectionSurvivesThePageBeingRebuilt() {
        let host = ModuleViewModel(transport: SilentTransport())
        var page: LeftoversViewModel? = LeftoversViewModel.shared(vm: host)
        page?.selected = ["/one", "/two"]

        page = nil                                  // the sidebar click
        let returned = LeftoversViewModel.shared(vm: host)

        XCTAssertEqual(returned.selected, ["/one", "/two"])
    }

    /// Switching the module off deallocates the engine; the transport held here
    /// survives and answers everything with empty Data from then on, so the
    /// cache is keyed to the host view model rather than merely "exists".
    func testANewHostViewModelIsNotAnsweredByTheOldInstance() {
        let first = LeftoversViewModel.shared(vm: ModuleViewModel(transport: SilentTransport()))

        let new = ModuleViewModel(transport: SilentTransport())
        let second = LeftoversViewModel.shared(vm: new)

        XCTAssertFalse(first === second, "the page came back talking to a dead engine")
        XCTAssertTrue(second.vm === new, "the cached instance is not the one this page hosts")
    }

    func testSwitchingTheModuleOffDropsTheCachedInstance() async {
        let host = ModuleViewModel(transport: SilentTransport())
        let first = LeftoversViewModel.shared(vm: host)

        NotificationCenter.default.post(name: .helmModuleDisabled,
                                        object: LeftoversDescriptor.id.rawValue)

        // The observer runs on the main queue, so the drop lands a turn later:
        // waited for as a condition, not as a fixed number of yields.
        var second = first
        for _ in 0..<1000 where second === first {
            await Task.yield()
            second = LeftoversViewModel.shared(vm: host)
        }
        XCTAssertFalse(first === second,
                       "the module was switched off and its cached view model stayed reachable")
    }
}
