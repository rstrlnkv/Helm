import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// **The page is built on the thread that draws, so building it must be free.**
///
/// `DuplicatesViewModel` is `@MainActor` and its first draw reads the keep policy —
/// which verifies a seal, which needs the key, which comes from the login
/// keychain. On an ad-hoc build the cdhash changes with every build, no access
/// list an earlier one wrote still names this one, and the answer is a modal
/// authorization dialog rather than data, on the thread that draws.
///
/// So the policy starts at the standard belief and arrives from a task
/// `appear()` holds: a load nobody can await is a load every test races.
@MainActor
final class ThePageNeverWaitsForTheKeychainTests: XCTestCase {

    private var store: NamespacedStore!

    override func setUp() async throws {
        store = duplicatesStore(folder: "\(home)/Downloads")
    }

    /// The production wiring, spelled the way the module spells it: the probe
    /// stands in for the login keychain and `SealKeyCache` for what is in front
    /// of it, so «warm» here means what it means in the app.
    private func model(over keys: SealKeyPort) -> DuplicatesViewModel {
        DuplicatesViewModel(work: AnsweringWork(groups: []),
                            store: store, settings: SettingGuard(keys: keys), chooseFolder: { nil })
    }

    // MARK: - Cold

    /// Building the page asks the keychain nothing at all.
    func testBuildingThePageAsksTheKeychainNothing() {
        let probe = SealKeyProbe()

        _ = model(over: SealKeyCache(probe))

        XCTAssertEqual(probe.reads, 0, """
            the page's own construction went to the keychain, which on an ad-hoc build is a modal \
            authorization dialog — and this initialiser runs on the thread that draws
            """)
    }

    /// With a keychain that is **still deciding**, the page is built and answers
    /// while the port is parked mid-call.
    ///
    /// A port that answers instantly is over before the code under test is
    /// reached, so the probe is held on its gate. The valve keeps a page that
    /// *does* wait from hanging the suite: it fails a deadline instead.
    func testThePageIsBuiltWhileTheKeychainIsStillDeciding() async {
        let gate = DispatchSemaphore(value: 0)
        let probe = SealKeyProbe(gate: gate)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { gate.signal() }

        let started = Date()
        let dvm = model(over: SealKeyCache(probe))
        dvm.appear()
        let built = Date().timeIntervalSince(started)

        XCTAssertLessThan(built, 1, """
            building the page waited for the keychain — on an ad-hoc build that wait is a modal \
            authorization dialog, and this is the thread that draws
            """)
        XCTAssertEqual(dvm.policy, .standard, "and it answers while the keychain is still deciding")
        // Released here rather than left to the valve: a healthy page then costs
        // the suite nothing, and only a page that waited pays the two seconds.
        gate.signal()
        await dvm.firstLoad?.value
    }

    /// And what it shows meanwhile is the standard belief, **with a policy really
    /// stored**: an empty store answers `.standard` however the page is written,
    /// so a page that had read the plist inside `init` would pass that.
    func testThePageOpensOnTheStandardBeliefWhileTheKeyIsStillCold() {
        let probe = SealKeyProbe()
        DuplicatesSettings.setKeepPolicy(.byDate, in: store, guardedBy: SettingGuard(keys: probe))

        let dvm = model(over: SealKeyCache(probe))
        dvm.appear()

        XCTAssertEqual(dvm.policy, .standard)
    }

    // MARK: - Warm

    /// And the stored policy still arrives, once the key is in hand.
    ///
    /// **The page's own cache starts cold**, which is what makes this about the
    /// page: sealing through a guard that shares the model's cache would warm it
    /// before the model existed, and the assertion below would hold with
    /// `warmKey()` dropped.
    func testTheStoredPolicyArrivesOnceTheKeyIsInHand() async {
        let probe = SealKeyProbe()
        DuplicatesSettings.setKeepPolicy(.byDate, in: store, guardedBy: SettingGuard(keys: probe))
        let dvm = model(over: SealKeyCache(probe))
        dvm.appear()

        await dvm.firstLoad?.value

        XCTAssertEqual(dvm.policy, .byDate,
                       "the page never caught up with what the engine has stored")
    }

    /// The round trip happens, and it happens somewhere else. Both halves: a
    /// check that the keychain was not asked on the main thread passes by itself
    /// when the keychain was never asked at all.
    func testTheKeyIsFetchedOffTheThreadThatDraws() async {
        let probe = SealKeyProbe()
        let dvm = model(over: SealKeyCache(probe))
        dvm.appear()

        await dvm.firstLoad?.value

        XCTAssertGreaterThan(probe.reads, 0,
                             "the key was never fetched, so the assertion below is about nothing")
        XCTAssertFalse(probe.wasAskedOnTheMainThread, """
            the round trip was made on the thread that draws — suspending is not the same as \
            handing the work to another thread
            """)
    }

    // MARK: - And the page reads the cheap one

    /// A keychain that cannot answer — locked at login — leaves the page on the
    /// standard belief rather than waiting for one. It is the answer the engine
    /// applies in the same state, so the screen and the sweep still agree.
    func testAKeychainThatCannotAnswerLeavesTheStandardBelief() async {
        let silent = SilentSealKey()
        let dvm = model(over: SealKeyCache(silent))
        dvm.appear()

        await dvm.firstLoad?.value

        XCTAssertGreaterThan(silent.reads, 0, "nothing ever asked, so the refusal never happened")
        XCTAssertEqual(dvm.policy, .standard)
    }
}
