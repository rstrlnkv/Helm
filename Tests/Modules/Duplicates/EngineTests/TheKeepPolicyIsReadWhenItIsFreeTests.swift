import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// **Reading what is in force costs a keychain round trip, and one of its two
/// readers is the thread that draws.**
///
/// The engine reads the policy from its own actor and can afford to wait; the
/// page reads it from `@MainActor init`, where the wait is a modal authorization
/// dialog on every ad-hoc build — 19,09 s of one in
/// `HelmApp_2026-08-19-235500_MacBook.hang`, one target over. So there is a
/// second way to ask that answers «not yet» instead of waiting, in the same file
/// that answers «what is in force»: the screen and the sweep still read one
/// implementation, and only the *waiting* is the caller's choice.
///
/// Nil is a third answer, kept apart from a broken seal on purpose. Folding them
/// would be the same reading twice over: a slow keychain reported as a forged
/// setting.
final class TheKeepPolicyIsReadWhenItIsFreeTests: XCTestCase {

    private var store: NamespacedStore!
    private var probe: SealKeyProbe!
    /// The production wiring: the cache is what makes a warm read memory rather
    /// than a second round trip, so a test of «if warm» without it is a test of
    /// something the app does not have.
    private var settings: SettingGuard!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: DuplicatesEngine.moduleID,
                                backing: InMemoryKeyValueStore())
        probe = SealKeyProbe()
        settings = SettingGuard(keys: SealKeyCache(probe))
    }

    /// Sealed through the probe directly, so the value is planted without warming
    /// the cache the reading below goes through.
    private func plant(_ policy: KeepPolicy) {
        DuplicatesSettings.setKeepPolicy(policy, in: store,
                                         guardedBy: SettingGuard(keys: probe))
    }

    // MARK: - Cold

    func testAColdKeyIsNotAnAnswer() {
        plant(.byDate)

        XCTAssertNil(DuplicatesSettings.keepPolicyIfWarm(in: store, guardedBy: settings),
                     "an answer was given that only a keychain round trip could support")
    }

    func testAColdReadDoesNotGoToTheKeychain() {
        plant(.byDate)
        let planted = probe.reads

        _ = DuplicatesSettings.keepPolicyIfWarm(in: store, guardedBy: settings)

        XCTAssertEqual(probe.reads, planted,
                       "reading the policy went to the keychain, which on an ad-hoc build is a "
                       + "modal dialog — and one of this reading's two callers draws")
    }

    /// Nothing stored is «not yet» too, and it has to be: that branch is where
    /// the blocking read *establishes* the key, which is the most expensive round
    /// trip of them all and the one a first launch pays.
    func testNothingStoredIsAlsoNotAnsweredWhileTheKeyIsCold() {
        XCTAssertNil(DuplicatesSettings.keepPolicyIfWarm(in: store, guardedBy: settings))
        XCTAssertEqual(probe.reads, 0, "the fresh-install branch established the key inline")
    }

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
