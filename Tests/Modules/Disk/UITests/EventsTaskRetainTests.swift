import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// `DiskViewModel.init` starts `eventsTask = Task { [weak self] in await
/// self?.observeEvents() }` and nothing ever cancels it — there is no
/// `deinit`. `observeEvents()` is an instance method: once the weak capture
/// resolves and the call is under way, Swift needs `self` for the rest of
/// that call frame, so the `for await` loop — which normally never returns,
/// because `LocalTransport` never finishes its stream — holds `self` alive
/// for as long as the loop runs. That is forever, once it has started.
///
/// `DiskViewModel.shared(vm:)` and `ModuleUICache.dropWhenDisabled` only drop
/// the CACHE's reference (ARCHITECTURE.md § Memory: "drops the cached
/// instance, and the reclaim above hands the pages back"). If the view model
/// is also kept alive by its own task, dropping the cache does not free it —
/// the scan tree, `DiskNode` and all, stays reachable, and `LocalTransport`
/// keeps a subscriber registered for a view model nothing else can reach.
/// `DuplicatesViewModel` shows the fix already exists elsewhere in the
/// codebase: `deinit { eventsTask?.cancel() }`.
@MainActor
final class EventsTaskRetainTests: XCTestCase {
    func testDiskViewModelIsReleasedOnceNothingElseHoldsIt() async {
        let transport = LocalTransport()
        let vm = ModuleViewModel(transport: transport)
        let directory = temporaryStoreDirectory("disk-retain")
        var dvm: DiskViewModel? = DiskViewModel(vm: vm, store: ScanStore(directory: directory))
        weak var weakDvm = dvm

        // Let the view model actually run first — this is the realistic case:
        // a page was open, `observeEvents()`'s `for await` started and is
        // parked waiting on the transport, exactly as it would be after the
        // user actually used the module. Only THEN does the module get
        // switched off / the cache dropped, which is what the test below
        // simulates by clearing the only other strong reference.
        for _ in 0..<200 { await Task.yield() }

        dvm = nil
        for _ in 0..<200 { await Task.yield() }

        XCTAssertNil(weakDvm, "DiskViewModel outlived its last known strong reference — "
                     + "its own eventsTask is retaining it, so ModuleUICache.dropWhenDisabled "
                     + "does not actually free a disabled module's view model once the page "
                     + "has been used")
    }
}
