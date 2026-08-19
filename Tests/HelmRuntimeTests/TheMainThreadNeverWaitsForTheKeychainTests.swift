import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// **Warming the key off the main thread is not the same as the main thread
/// never waiting for it, and the app shipped believing it was.**
///
/// Measured from `HelmApp_2026-08-19-235500_MacBook.hang`: 19,09 s of an
/// unresponsive settings window on `0.11.0-dev.1`. Two threads, one lock.
///
/// - `SettingGuard.warmKey()` was inside `KeychainSealKey.read()` →
///   `SecItemCopyMatching` → `ClientSession::decrypt` → `mach_msg`, parked in
///   securityd behind the modal authorization dialog every ad-hoc build earns.
/// - The main thread, answering `NSApplication.didBecomeActive`, read
///   `AppSettings.disabledScans` → `SettingGuard.verdict` → `SealKeyCache.key()`
///   → `_pthread_mutex_firstfit_lock_slow`, which the report names outright:
///   *blocked by turnstile … waiting for … thread 0x1bc925*.
///
/// `SealKeyCache` holds its lock **across** the source's own call, deliberately,
/// so that two callers arriving together cost one dialog rather than two — and
/// `TheSealKeyIsAskedOnceAndNotOnMainTests` proves that half. What neither that
/// file nor this one could say before was what the second caller pays, and when
/// the second caller is the thread that draws, it pays the whole dialog.
///
/// So there is a second way to ask: `keyIfWarm()` answers from what is already
/// in hand and never makes, or waits for, a round trip. Nil from it means «not
/// yet», which is a third answer and not a refusal — folding it into `.broken`
/// would tell somebody their settings had been forged because a keychain was
/// slow.
final class TheMainThreadNeverWaitsForTheKeychainTests: XCTestCase {

    // MARK: - The port answers from what it holds

    func testAnUnwarmedCacheRefusesRatherThanFetches() {
        let source = SealKeyProbe()
        let cache = SealKeyCache(source)
        XCTAssertNil(cache.keyIfWarm(), "there has been no fetch, so there is nothing to hand back")
        XCTAssertEqual(source.reads, 0, """
            asking for the key already in hand went to the keychain, which on an ad-hoc build \
            is the modal dialog this call exists to avoid
            """)
    }

    func testAWarmedCacheAnswersWithoutAnotherRoundTrip() throws {
        let source = SealKeyProbe()
        let cache = SealKeyCache(source)
        let fetched = try XCTUnwrap(cache.key())
        let warm = try XCTUnwrap(cache.keyIfWarm(), "the fetch above put the key in hand")
        XCTAssertEqual(warm.material, fetched.material)
        XCTAssertEqual(source.reads, 1)
    }

    /// First use is the trust-on-first-use door, and it is spent by the run that
    /// *created* the item. A key handed back from memory is by definition not
    /// that run, so this door is shut here whatever the source once answered.
    func testAKeyHandedBackFromMemoryNeverSpendsFirstUse() throws {
        let cache = SealKeyCache(SealKeyProbe())
        XCTAssertEqual(try XCTUnwrap(cache.key()).firstUse, true, "the run that created it")
        XCTAssertEqual(try XCTUnwrap(cache.keyIfWarm()).firstUse, false)
    }

    // MARK: - The hang itself

    /// **The report, written as a test.** A fetch is inside the source and
    /// cannot leave; a second caller arrives; it must be answered.
    ///
    /// The second caller runs on a queue rather than on this thread on purpose:
    /// a `keyIfWarm()` that blocks would hang the test rather than fail it, and
    /// a guard that hangs tells nobody anything. On a queue the wait below
    /// fails with a sentence. The property under test — *does not wait for a
    /// round trip somebody else is making* — is about the lock, not about which
    /// thread holds it, so nothing is lost by asking it from here.
    func testACallerIsAnsweredWhileAFetchIsStillInFlight() {
        let gate = DispatchSemaphore(value: 0)
        let source = SealKeyProbe(gate: gate)
        let cache = SealKeyCache(source)

        let fetchReturned = expectation(description: "the fetch returned")
        DispatchQueue.global().async {
            _ = cache.key()
            fetchReturned.fulfill()
        }
        XCTAssertTrue(source.waitUntilAsked(), """
            the fetch never reached the keychain, so nothing below is about a caller arriving \
            while one is in flight
            """)

        let answered = expectation(description: "the second caller was answered")
        DispatchQueue.global().async {
            _ = cache.keyIfWarm()
            answered.fulfill()
        }
        wait(for: [answered], timeout: 2)

        gate.signal()
        wait(for: [fetchReturned], timeout: 5)
        XCTAssertEqual(source.reads, 1, "the second caller made a round trip of its own")
    }

    /// And the answer while a fetch is in flight is «not yet», not a key: the
    /// fetch has not stored anything, and inventing one would seal settings with
    /// material no other reader will ever agree with.
    func testTheAnswerWhileAFetchIsInFlightIsNotYetRatherThanAKey() {
        let gate = DispatchSemaphore(value: 0)
        let source = SealKeyProbe(gate: gate)
        let cache = SealKeyCache(source)
        let box = KeyBox()

        let fetchReturned = expectation(description: "the fetch returned")
        DispatchQueue.global().async {
            _ = cache.key()
            fetchReturned.fulfill()
        }
        XCTAssertTrue(source.waitUntilAsked())

        let answered = expectation(description: "the second caller was answered")
        DispatchQueue.global().async {
            box.put(cache.keyIfWarm())
            answered.fulfill()
        }
        wait(for: [answered], timeout: 2)
        XCTAssertNil(box.taken ?? nil, "a key was handed out that no fetch had stored")

        gate.signal()
        wait(for: [fetchReturned], timeout: 5)
    }

    // MARK: - The verdict the screen takes

    /// The screen's half. Before it reads a sealed setting at all, the main
    /// actor asks whether reading one is free — and asking *that* has to be
    /// free, or the question has moved the cost rather than avoided it.
    func testAskingWhetherTheKeyIsInHandCostsNoRoundTrip() {
        let source = SealKeyProbe()
        let guarded = SettingGuard(keys: SealKeyCache(source))

        XCTAssertFalse(guarded.isWarm, "nothing has been fetched")
        XCTAssertEqual(source.reads, 0, "asking whether the key is in hand went to the keychain")
    }

    func testAGuardIsWarmOnceTheKeyHasBeenFetched() async {
        let source = SealKeyProbe()
        let guarded = SettingGuard(keys: SealKeyCache(source))
        await guarded.warmKey()

        XCTAssertTrue(guarded.isWarm)
        // Warming *is* the run that created the item, so it is the ask that
        // spent first use — and an unsealed value is a refusal ever after. The
        // point here is the round trips, not the verdict: it is still computed
        // from live values, and computing it costs nothing more.
        XCTAssertEqual(guarded.verdict(payload: Data("disk".utf8), mac: ""), .broken)
        XCTAssertEqual(source.reads, 1, "a verdict taken while warm went back to the keychain")
    }

    /// A keychain that refuses leaves the guard cold, and cold is not sealed and
    /// not broken — it is «not yet», which is the answer a screen draws as «not
    /// read» rather than as «somebody rewrote your settings».
    func testAGuardOverARefusingKeychainStaysCold() async {
        let guarded = SettingGuard(keys: SealKeyCache(SilentSealKey()))
        await guarded.warmKey()
        XCTAssertFalse(guarded.isWarm)
    }

    /// A keychain that will not answer leaves nothing in hand, so the warm ask
    /// keeps saying «not yet» — and, unlike the blocking one, never goes back to
    /// ask again. A refusal is not remembered; it is simply never fetched here.
    func testAKeychainThatRefusesLeavesTheWarmAskSayingNotYet() {
        let source = SilentSealKey()
        let cache = SealKeyCache(source)
        XCTAssertNil(cache.key())
        XCTAssertNil(cache.keyIfWarm())
        XCTAssertEqual(source.reads, 1, "the warm ask went back to a keychain that had refused")
    }

    /// What a background caller answered, across a queue boundary.
    private final class KeyBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: SealKey??
        func put(_ key: SealKey?) { lock.withLock { stored = key } }
        var taken: SealKey?? { lock.withLock { stored } }
    }
}
