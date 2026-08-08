import HelmContract
import HelmRuntime
import HelmUI
import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// One object behind three surfaces.
///
/// The descriptor, the panel tile and the settings page all draw this module's
/// state, and Settings tears its page down on every visit — so a page-scoped
/// `@StateObject` would be a new view model each time, subscribing to the
/// transport again and showing whatever it had decoded since. The session's
/// remaining time, which is the one number this module exists to show, would
/// restart from nothing on the second visit to the page.
///
/// Asserted on identity, not on values: two view models fed by the same
/// transport agree about almost everything, so a count or a flag would be
/// satisfied by the very duplication this is about.
@MainActor
final class SharedViewModelTests: XCTestCase {

    func testTheSameHostViewModelAlwaysGetsTheSameInstance() {
        let host = ModuleViewModel(transport: LocalTransport())

        let first = KeepAwakeViewModel.shared(vm: host)
        let second = KeepAwakeViewModel.shared(vm: host)

        XCTAssertTrue(first === second,
                      "the tile and the page hold two view models of one module, so a "
                      + "session started on one is invisible to the other")
    }

    /// Switching the module off and on builds a new host view model, and the old
    /// transport's handler — held weakly by the engine — answers everything with
    /// empty `Data` from then on. Keyed to the host, not merely "exists".
    func testANewHostViewModelIsNotAnsweredByTheOldInstance() {
        let old = ModuleViewModel(transport: LocalTransport())
        let first = KeepAwakeViewModel.shared(vm: old)

        let new = ModuleViewModel(transport: LocalTransport())
        let second = KeepAwakeViewModel.shared(vm: new)

        XCTAssertFalse(first === second, "the page came back talking to a dead engine")
        XCTAssertTrue(second.vm === new, "the cached instance is not the one this page hosts")
    }

    /// And switching the module off drops the cache rather than leaving it
    /// reachable: the view model holds a task reading the transport's events for
    /// as long as it is alive.
    func testSwitchingTheModuleOffDropsTheCachedInstance() async {
        let host = ModuleViewModel(transport: LocalTransport())
        let first = KeepAwakeViewModel.shared(vm: host)

        NotificationCenter.default.post(name: .helmModuleDisabled,
                                        object: KeepAwakeDescriptor.id.rawValue)

        // The observer runs on the main queue, so the drop lands a turn later:
        // waited for as a condition, not as a fixed number of yields.
        var second = first
        for _ in 0..<1000 where second === first {
            await Task.yield()
            second = KeepAwakeViewModel.shared(vm: host)
        }
        XCTAssertFalse(first === second,
                       "the module was switched off and its cached view model stayed "
                       + "reachable, still reading the transport")
    }
}
