import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Homebrew_Engine

/// **A suite run must not fetch anything from `formulae.brew.sh`.**
///
/// `FilePopularityStore()` — the convenience init, the one `HomebrewSystemPorts`
/// uses — bound the live transfer unconditionally, and three files in this
/// target call `ModuleHost.bootstrap()`, which enables every module in the
/// registry and reaches `HomebrewEngine.activate()`, which starts the refresh.
/// So `swift test` downloaded both analytics documents — about 834 KiB — from a
/// third party on every run, on whatever network the machine happened to be on,
/// and nothing failed when it failed: the store's whole design is to fall back
/// to today's behaviour on a refusal.
///
/// The store's own tests all call `refreshIfDue` deliberately with a fake
/// transfer, which is why the guard sits on the transfer the convenience init
/// chooses (`FilePopularityStore.liveTransfer`) and not inside `refreshIfDue`.
///
/// **Why a counter of attempts and not a listener or a stub.** A request that
/// is never sent leaves nothing to observe, and an assertion built on "no bytes
/// came back" passes on any machine that is merely offline — which is the one
/// failure mode this has to survive, since a laptop with no network is exactly
/// where the defect is invisible. `FilePopularityStore.wireAsks` counts the
/// hand-over to `URLSession` itself, so it moves whether or not anything
/// answers.
final class ASuiteRunAsksHomebrewNothingTests: XCTestCase {

    func testAStoreBuiltTheLiveWayNeverReachesTheNetwork() async {
        let before = FilePopularityStore.wireAsks.count

        // Built exactly as `HomebrewSystemPorts` builds it, and asked to do the
        // one thing that can reach the wire. The directory is the redirected
        // scratch one under a test runner, so nothing lands in a real folder
        // either way.
        await FilePopularityStore().refreshIfDue()

        XCTAssertEqual(FilePopularityStore.wireAsks.count, before,
                       "a store built the live way handed a request to URLSession under a "
                       + "test runner — every `swift test` run downloads Homebrew's two "
                       + "analytics documents from formulae.brew.sh, silently, and nothing "
                       + "fails when that fails")
    }

    /// The guard must be the *live* path's, not something the store does to
    /// every transfer: a store handed a fake one still has to run, or every
    /// test of this type would be asserting about nothing.
    func testAStoreHandedATransferStillUsesIt() async {
        let wire = PopularityAskCounter()
        let store = FilePopularityStore(directory: scratchDirectory("homebrew-wire"),
                                        transfer: wire.transfer)

        await store.refreshIfDue()

        XCTAssertGreaterThan(wire.count, 0,
                             "the store asked its own transfer nothing, so the guard above is "
                             + "being proved by a refresh that does not work at all")
    }
}

/// One side of the boundary: a transfer that refuses, and counts.
private final class PopularityAskCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var asks = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return asks }

    /// Synchronous, because a lock may not be taken in an asynchronous context
    /// — and the transfer below is one.
    private func record() { lock.lock(); asks += 1; lock.unlock() }

    var transfer: FilePopularityStore.Transfer {
        { [self] _ in
            record()
            throw URLError(.notConnectedToInternet)
        }
    }
}
