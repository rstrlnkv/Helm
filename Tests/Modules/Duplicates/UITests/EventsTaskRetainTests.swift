import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// Control for the same question `Module_Disk_UITests.EventsTaskRetainTests`
/// asks about `DiskViewModel`: does `deinit { eventsTask?.cancel() }` actually
/// let the view model go once its `observeEvents()` loop has started? If an
/// instance's own `for await` retains `self` for the call's whole duration —
/// which never ends, because `LocalTransport` never finishes its stream —
/// `deinit` cannot run to call `cancel()` in the first place, and the
/// `Task<Void, Never>?` field would be exactly as inert as `DiskViewModel`'s.
@MainActor
final class EventsTaskRetainTests: XCTestCase {
    func testDuplicatesViewModelIsReleasedOnceNothingElseHoldsIt() async {
        let transport = LocalTransport()
        let store = NamespacedStore(namespace: "test.duplicates.retain.\(UUID().uuidString)",
                                    backing: UserDefaults.standard)
        var dvm: DuplicatesViewModel? = DuplicatesViewModel(
            vm: ModuleViewModel(transport: transport), store: store)
        weak var weakDvm = dvm

        // Let observeEvents() actually start and park on the stream, as it
        // would after a real page had been open for a moment.
        for _ in 0..<200 { await Task.yield() }

        dvm = nil
        for _ in 0..<200 { await Task.yield() }

        XCTAssertNil(weakDvm, "DuplicatesViewModel outlived its last known strong reference "
                     + "even with deinit { eventsTask?.cancel() } — if this fails, the deinit "
                     + "fix cannot be running either, because the same self-retain that traps "
                     + "DiskViewModel would also stop this deinit from ever firing")
    }
}
