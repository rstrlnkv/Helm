import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// Warming the key off the main thread is not the same as the main thread
/// never waiting for it.
///
/// `SealKeyCache` holds its lock across the source's own call, so two callers
/// arriving together cost one dialog rather than two
/// (`TheSealKeyIsAskedOnceAndNotOnMainTests`). The second caller then waits for
/// the whole round trip, and when it is the main thread reading a sealed
/// setting behind a warm-up parked on an authorization dialog, the window
/// hangs.
///
/// So there is a second way to ask: `keyIfWarm()` answers from what is in hand
/// and never makes, or waits for, a round trip. Its nil means «not yet», a third
/// answer and not a refusal: folding it into `.broken` would tell somebody their
/// settings had been forged because a keychain was slow.
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

    /// A fetch is inside the source and cannot leave; a second caller arrives
    /// and must be answered.
    ///
    /// The second caller runs on a queue, so a `keyIfWarm()` that blocks fails
    /// the wait below rather than hanging the test. The property is about the
    /// lock, not about which thread holds it.
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
        let box = Locked<SealKey??>(nil)  // what a background caller answered, across a queue boundary

        let fetchReturned = expectation(description: "the fetch returned")
        DispatchQueue.global().async {
            _ = cache.key()
            fetchReturned.fulfill()
        }
        XCTAssertTrue(source.waitUntilAsked())

        let answered = expectation(description: "the second caller was answered")
        DispatchQueue.global().async {
            box.value = .some(cache.keyIfWarm())
            answered.fulfill()
        }
        wait(for: [answered], timeout: 2)
        XCTAssertNil(box.value ?? nil, "a key was handed out that no fetch had stored")

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
        // Warming created the item and spent first use, so an unsealed value
        // is refused. The point is the round trips, not the verdict.
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
}
