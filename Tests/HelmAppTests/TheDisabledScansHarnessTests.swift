import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// Guards `DisabledScansTestCase.freshMac`: its two parameters reach the guard they build, or the page tests
/// that pass them would run against a bare probe and a probe that never holds, and stay green all the same.
@MainActor
final class TheDisabledScansHarnessTests: DisabledScansTestCase {

    /// `cached: true` puts a `SealKeyCache` over the probe: a second seal costs no second ask, a bare probe is
    /// asked again.
    func testCachedPutsTheProbeBehindTheCache() {
        let cached = freshMac(cached: true)
        AppSettings.disabledScans = ["disk"]
        AppSettings.disabledScans = ["disk", "mail"]
        XCTAssertGreaterThan(cached.reads, 0, "nothing was sealed, so nothing was measured")
        let cachedReads = cached.reads

        let bare = freshMac()
        AppSettings.disabledScans = ["disk"]
        AppSettings.disabledScans = ["disk", "mail"]
        XCTAssertGreaterThan(bare.reads, cachedReads, "the cache made no difference to the asks")
    }

    /// `gate:` is the probe's own gate: a read holds shut until the test opens it.
    func testGateHoldsTheProbesRead() {
        let gate = DispatchSemaphore(value: 0)
        let keychain = freshMac(gate: gate)
        let done = expectation(description: "the write returned")
        DispatchQueue.global().async {
            AppSettings.disabledScans = ["disk"]
            done.fulfill()
        }
        XCTAssertTrue(keychain.waitUntilAsked(), "nobody reached the keychain, so nothing was held")
        XCTAssertEqual(keychain.reads, 0, "the read answered with the gate shut")
        gate.signal()
        gate.signal()
        wait(for: [done], timeout: 5)
        XCTAssertGreaterThan(keychain.reads, 0)
    }

    /// A harness test that starts dirty: a process starts clean, so deleting either clearing line of `freshMac`
    /// would change nothing in the page tests unless the state is dirtied first.
    func testFreshMacClearsTheValueAndItsMac() {
        AppSettings.store.set(["disk"], for: key)
        AppSettings.store.set("stale", for: macKey)
        _ = freshMac()
        XCTAssertNil(AppSettings.store.object(key), "the stored value survived freshMac")
        XCTAssertNil(AppSettings.store.object(macKey), "the stored MAC survived freshMac")
    }

    /// `tearDown` puts back the guard `setUp` found: a second setUp saves a probe's guard, a test swaps it, and
    /// the tearDown must bring the first back, or the next test class would seal through the wrong keychain.
    func testTearDownPutsTheSealGuardBack() async throws {
        let original = AppSettings.scanGuard
        defer { AppSettings.scanGuard = original }
        let saved = freshMac()
        try await setUp()
        let swapped = freshMac()
        try await tearDown()
        _ = AppSettings.scanGuard.seal(Data("x".utf8))
        XCTAssertGreaterThan(saved.reads, 0, "the guard setUp saved was not put back")
        XCTAssertEqual(swapped.reads, 0, "the test's guard outlived tearDown")
    }
}
