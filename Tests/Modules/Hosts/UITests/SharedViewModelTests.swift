import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// A sidebar click must not re-read the file and throw away what was typed.
///
/// Settings rebuilds a module's page on every visit, so a page-scoped
/// `@StateObject` is a new view model each time — and here that is the parsed
/// document and every unsaved edit in it. Disk, Leftovers, Uninstaller,
/// Homebrew, KeepAwake, Duplicates and Layout all cache per host view model for
/// the same reason.
@MainActor
final class SharedViewModelTests: XCTestCase {

    private let localhost = "127.0.0.1\tlocalhost\n"

    private func hosted() -> HostsUIWire {
        HostsUIWire.make(file: localhost, privileged: .declined)
    }

    func testTheSameHostViewModelAlwaysGetsTheSameInstance() {
        let wire = hosted()
        let first = HostsViewModel.shared(vm: wire.vm)
        addTeardownBlock { await MainActor.run { first.stop() } }

        XCTAssertTrue(first === HostsViewModel.shared(vm: wire.vm),
                      "a second visit to the page built a second view model, which is the "
                      + "parsed file and every unsaved edit thrown away")
        XCTAssertEqual(wire.transport.subscriberCount, 1,
                       "a second page opened a second subscription")
    }

    /// Switching the module off deallocates the engine; the transport held here
    /// survives and answers everything with empty Data from then on, so the
    /// cache is keyed to the host view model rather than merely "exists".
    func testANewHostViewModelIsNotAnsweredByTheOldInstance() {
        let first = HostsViewModel.shared(vm: hosted().vm)
        let next = hosted()
        let second = HostsViewModel.shared(vm: next.vm)
        addTeardownBlock { await MainActor.run { first.stop(); second.stop() } }

        XCTAssertFalse(first === second, "the page came back talking to a dead engine")
        XCTAssertTrue(second.vm === next.vm, "the cached instance is not the one this page hosts")
    }

    /// **A stopped model is not handed out again.** The cache and `stop()` are
    /// otherwise a trap: the stopped instance stays cached, so the next page to
    /// open gets a model whose event task is cancelled — no snapshot, ever, for
    /// the life of the process.
    func testAStoppedModelIsNotHandedToTheNextPage() async {
        let wire = hosted()
        let first = HostsViewModel.shared(vm: wire.vm)
        first.stop()

        let second = HostsViewModel.shared(vm: wire.vm)
        addTeardownBlock { await MainActor.run { second.stop() } }
        XCTAssertFalse(first === second, "the next page was handed the stopped model")
        await second.firstLoad?.value
        await waitUntil("the replacement is listening") { second.onDisk == localhost }
        XCTAssertEqual(second.text, localhost)
    }

    /// The module being switched off is a fact that stops being true on its
    /// own, so it arrives as an event rather than being noticed later: the
    /// cached model is dropped **and** its subscription ends, or a model with a
    /// live task sits on a transport whose engine is gone.
    func testSwitchingTheModuleOffDropsTheCachedInstanceAndItsSubscription() async {
        let wire = hosted()
        let first = HostsViewModel.shared(vm: wire.vm)
        await first.firstLoad?.value
        await waitUntil("the first snapshot arrived") { first.onDisk == localhost }

        NotificationCenter.default.post(name: .helmModuleDisabled,
                                        object: HostsDescriptor.id.rawValue)

        // The observer runs on the main queue, so the drop lands a turn later:
        // waited for as a condition, not as a fixed number of yields.
        await waitUntil("the subscription ended") { wire.transport.subscriberCount == 0 }
        let second = HostsViewModel.shared(vm: wire.vm)
        addTeardownBlock { await MainActor.run { second.stop() } }
        XCTAssertFalse(first === second,
                       "the module was switched off and its cached view model stayed reachable")
    }
}
