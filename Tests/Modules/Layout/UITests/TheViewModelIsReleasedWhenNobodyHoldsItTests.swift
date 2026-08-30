import HelmContract
import HelmRuntime
import HelmUI
import HelmTestSupport
import XCTest
@testable import Module_Layout_UI

/// `LayoutViewModel` starts a `for await` over the transport's events in `init`
/// and nothing else ever ends it — `LocalTransport` does not finish its stream.
/// If that task held `self`, `ModuleUICache.dropWhenDisabled` would drop only
/// the *cache's* reference: the view model would stay alive, the transport
/// would keep a subscriber registered for something nothing can reach, and
/// turning the module off would free nothing.
///
/// It does not, and the shape is the reason: `[weak self]` at the top plus
/// `guard let self else { break }` and a **synchronous** `handle(event)`. The
/// trap CLAUDE.md § Memory records is `await self?.method()`, where the strong
/// reference lives for as long as the call frame does — and for a loop that
/// never returns, that is the life of the app.
///
/// **The negative alone would pass vacuously**, which is why the positive comes
/// first: a `weak` reference to something that was never really constructed is
/// nil for the wrong reason, and the check would go green over a view model
/// that had died on line one. Disk and Duplicates have this guard; the other
/// five modules with a long-lived events task do not, and this is Layout's.
@MainActor
final class TheViewModelIsReleasedWhenNobodyHoldsItTests: XCTestCase {

    func testItIsAliveWhileHeldAndGoneOnceNothingHoldsIt() async {
        let transport = LocalTransport()
        let vm = ModuleViewModel(transport: transport)
        var lvm: LayoutViewModel? = LayoutViewModel.shared(vm: vm)
        weak var weakLvm = lvm

        // The realistic case: the page was open, the `for await` started and is
        // parked on the transport, exactly as after somebody used the module.
        for _ in 0..<200 { await Task.yield() }

        XCTAssertNotNil(weakLvm,
                        "precondition: the view model was gone before anything let go of it, so "
                        + "the assertion below would pass for the wrong reason")

        // `shared(vm:)` is keyed to the host view model — «turning the module
        // off and on again builds a new one, and the old cache would be talking
        // to a deallocated engine» — so asking for one over a different host is
        // how the cached reference is let go through the public door.
        let second = LayoutViewModel.shared(vm: ModuleViewModel(transport: LocalTransport()))
        withExtendedLifetime(second) {}
        lvm = nil
        for _ in 0..<200 { await Task.yield() }

        XCTAssertNil(weakLvm,
                     "LayoutViewModel outlived its last strong reference — its own events task is "
                     + "retaining it, so turning the module off frees nothing and the transport "
                     + "keeps a subscriber for a view model nobody can reach")
    }
}
