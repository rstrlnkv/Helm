import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Homebrew_Engine

/// **A suite run must not fetch anything from `formulae.brew.sh`.**
///
/// `FilePopularityStore()`, the convenience init `HomebrewSystemPorts` uses,
/// binds the live transfer, and tests here call `ModuleHost.bootstrap()`, which
/// reaches `HomebrewEngine.activate()` and starts the refresh. Unguarded, every
/// `swift test` would download both analytics documents from a third party,
/// and nothing would fail when that failed: the store falls back on a refusal.
///
/// **Why two checks and neither a counter nor a listener.** `liveTransfer` is a
/// `static var` and `NoWireUnderTest` is a named error, so the guard itself is
/// directly observable: calling it under a test runner must throw that error
/// rather than reach `URLSession`, and a laptop that is merely offline cannot
/// make this pass, because nothing here waits on bytes coming back — it is the
/// *branch*, not the network, under test.
///
/// That alone does not prove anything calls `liveTransfer`: the convenience
/// init could bind the unguarded `overTheNetwork` past it, and every store the
/// module's own tests build names its transfer. So the second check builds a
/// store the ordinary way and calls the transfer it holds.
final class ASuiteRunAsksHomebrewNothingTests: XCTestCase {

    func testALiveStoreRefusesTheWireUnderATestRunner() async {
        do {
            _ = try await FilePopularityStore.liveTransfer(
                URLRequest(url: FilePopularityStore.formulae.url))
            XCTFail("liveTransfer reached the network under a test runner")
        } catch is FilePopularityStore.NoWireUnderTest {
            // Exactly the refusal a suite run must get.
        } catch {
            XCTFail("liveTransfer threw \(error), not NoWireUnderTest")
        }
    }

    func testAStoreBuiltTheOrdinaryWayRefusesTheWireToo() async {
        let store = FilePopularityStore(directory: scratchDirectory("homebrew-ordinary"))
        do {
            _ = try await store.transfer(URLRequest(url: FilePopularityStore.formulae.url))
            XCTFail("a store built by the convenience init reached the network under a test runner")
        } catch is FilePopularityStore.NoWireUnderTest {
            // The convenience init bound the guarded transfer.
        } catch {
            XCTFail("the store's own transfer threw \(error), not NoWireUnderTest")
        }
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
