import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// **The keychain is asked once per process, and not on the thread that draws.**
///
/// A sealed setting's getter calls the key port on every read: three
/// `SecItemCopyMatching` round trips per coordinator tick, and one inside the
/// settings window's own construction. The round trip is not merely slow — on an
/// ad-hoc build the cdhash changes with every build, no ACL an earlier one wrote
/// still matches, and the answer is a modal authorization dialog. Held on the
/// main thread it stands in front of a window that has not drawn yet.
///
/// So the key is fetched once and kept, and the fetch has a way to happen off
/// the main actor. The *verdict* is still computed on every read — nothing here
/// caches whether a stored value is Helm's own, which is the live fact.
final class TheSealKeyIsAskedOnceAndNotOnMainTests: XCTestCase {

    func testTheSourceIsAskedOnceHoweverManyVerdictsAreTaken() {
        let source = SealKeyProbe()
        let guarded = SettingGuard(keys: SealKeyCache(source))
        let payload = Data("disk".utf8)
        let mac = guarded.seal(payload)
        for _ in 0..<20 { _ = guarded.verdict(payload: payload, mac: mac) }
        XCTAssertEqual(source.reads, 1,
                       "every verdict went to the keychain, which is a round trip per read "
                       + "and, on a build whose signature is new, a dialog per read")
    }

    /// The door the seal leaves open must still shut. `KeychainSealKey` answers
    /// `firstUse: true` only for the run that creates the item; a cache handing
    /// the same answer back for ever would leave `.adopt` granted for the life
    /// of the process, so anything written after Helm's first read would be
    /// adopted as Helm's own.
    func testTheCacheSpendsFirstUseExactlyOnce() throws {
        let cache = SealKeyCache(SealKeyProbe())
        XCTAssertEqual(try XCTUnwrap(cache.key()).firstUse, true, "the run that created it")
        XCTAssertEqual(try XCTUnwrap(cache.key()).firstUse, false)
        XCTAssertEqual(try XCTUnwrap(cache.key()).firstUse, false)
    }

    /// A source that found the item already there never grants first use, and
    /// the cache must not invent it.
    func testAKeyThatAlreadyExistedIsNeverFirstUse() throws {
        let source = SealKeyProbe()
        _ = source.key()                                   // the item exists now
        let cache = SealKeyCache(source)
        XCTAssertEqual(try XCTUnwrap(cache.key()).firstUse, false)
    }

    /// A locked keychain is a refusal, not an answer — and a refusal cached is
    /// an installation that never seals anything again until it is restarted.
    func testARefusalIsNotRemembered() {
        let source = SilentSealKey()
        let cache = SealKeyCache(source)
        XCTAssertNil(cache.key())
        XCTAssertNil(cache.key())
        XCTAssertEqual(source.reads, 2, "a keychain that was locked a moment ago can be open now")
    }

    /// The half that makes the settings window draw: warming happens off the
    /// main actor, so a dialog the keychain puts up does not hold the thread
    /// that lays the window out.
    @MainActor
    func testWarmingAsksTheSourceOffTheMainThread() async {
        let source = SealKeyProbe()
        let guarded = SettingGuard(keys: SealKeyCache(source))
        XCTAssertTrue(Thread.isMainThread, "or the test is not asking the question it says")
        await guarded.warmKey()
        XCTAssertEqual(source.reads, 1, "warming asked nothing, so the read is still to come")
        XCTAssertFalse(source.wasAskedOnTheMainThread,
                       "the keychain was asked on the main thread, which is where a modal "
                       + "authorization dialog blocks a window from drawing")
    }

    /// And the main thread is free *while* it answers, not merely afterwards.
    /// A gate that never opens is the only way to write this down: a source that
    /// returns instantly is over before the assertion is reached.
    @MainActor
    func testTheMainThreadRunsWhileTheKeychainIsStillAnswering() async {
        let gate = DispatchSemaphore(value: 0)
        let source = SealKeyProbe(gate: gate)
        let guarded = SettingGuard(keys: SealKeyCache(source))
        let warming = Task { await guarded.warmKey() }

        var turns = 0
        while turns < 50 {
            turns += 1
            await Task.yield()
        }
        XCTAssertEqual(source.reads, 0, "the gate is shut, so the source has not answered yet")
        gate.signal()
        await warming.value
        XCTAssertEqual(source.reads, 1)
    }
}
