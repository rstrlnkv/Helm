import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// The store, the probe and the guard both halves read the keep policy through:
/// one rig under the warm and the cold class, which stay two classes under their
/// own names.
class KeepPolicyCacheRig: XCTestCase {

    var store: NamespacedStore!
    var probe: SealKeyProbe!
    /// The production wiring: the cache is what makes a warm read memory rather
    /// than a second round trip, so a test of «if warm» without it is a test of
    /// something the app does not have.
    var settings: SettingGuard!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: DuplicatesEngine.moduleID,
                                backing: InMemoryKeyValueStore())
        probe = SealKeyProbe()
        settings = SettingGuard(keys: SealKeyCache(probe))
    }

    /// Sealed through the probe directly, so the value is planted without warming
    /// the cache the reading below goes through.
    func plant(_ policy: KeepPolicy) {
        DuplicatesSettings.setKeepPolicy(policy, in: store,
                                         guardedBy: SettingGuard(keys: probe))
    }
}

/// **Reading what is in force costs a keychain round trip, and one of its two
/// readers is the thread that draws.**
///
/// The engine reads the policy from its own actor and can afford to wait; the
/// page reads it on the main actor, where the wait is a modal authorization
/// dialog on every ad-hoc build. So a second way to ask answers «not yet»
/// instead of waiting, in the same file that answers «what is in force»: the
/// screen and the sweep read one implementation, and only the *waiting* is the
/// caller's choice.
///
/// Nil is a third answer, kept apart from a broken seal on purpose. Folding them
/// would be the same reading twice over: a slow keychain reported as a forged
/// setting.
final class TheKeepPolicyIsReadWhenItIsFreeTests: KeepPolicyCacheRig {

    // MARK: - Warm

    func testTheStoredPolicyIsAnsweredOnceTheKeyIsInHand() async {
        plant(.byDate)
        await settings.warmKey()

        XCTAssertEqual(DuplicatesSettings.keepPolicyIfWarm(in: store, guardedBy: settings), .byDate)
    }

    func testNothingStoredIsTheStandardBeliefOnceTheKeyIsInHand() async {
        await settings.warmKey()

        XCTAssertEqual(DuplicatesSettings.keepPolicyIfWarm(in: store, guardedBy: settings),
                       .standard)
    }

    /// The refusal is not softened by the read being cheap. A policy something
    /// else wrote is the standard belief — the direction
    /// `TheKeepPolicyIsSealedWhereStoredTests` records — and not the value in the
    /// file.
    func testAPolicySomethingElseWroteIsStillTheStandardBelief() async {
        plant(.byPlace)
        // The forged value is the one that is not the default, or a reader that
        // skipped the seal entirely would satisfy this too.
        store.set(KeepPolicy.byDate.rawValue, for: DuplicatesSettings.keepPolicyKey)
        await settings.warmKey()

        XCTAssertEqual(DuplicatesSettings.keepPolicyIfWarm(in: store, guardedBy: settings),
                       .standard)
    }

    /// A keychain that cannot answer stays «not yet» rather than becoming a
    /// verdict. `SilentSealKey` is the locked-at-login case, and a caller that
    /// read its nil as a refusal would tell somebody their settings were forged
    /// because the keychain was shut.
    func testAKeychainThatCannotAnswerNeverBecomesWarm() async {
        let silent = SilentSealKey()
        let settings = SettingGuard(keys: SealKeyCache(silent))
        DuplicatesSettings.setKeepPolicy(.byDate, in: store, guardedBy: SettingGuard(keys: probe))

        await settings.warmKey()

        XCTAssertGreaterThan(silent.reads, 0, "nothing ever asked, so the refusal never happened")
        XCTAssertNil(DuplicatesSettings.keepPolicyIfWarm(in: store, guardedBy: settings))
    }
}
