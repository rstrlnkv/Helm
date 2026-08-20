import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The fixture every page test in this target is built on can finish its read.
///
/// `duplicatesModel` handed the page a bare `PlantedSealKey`, which takes
/// `SealKeyPort`'s default `keyIfWarm() -> nil` — so `SettingGuard.isWarm` was
/// false for ever, `DuplicatesSettings.keepPolicyIfWarm` answered «not yet»
/// whatever was stored, and the popup sat on the default however long a test
/// waited. That is a keychain permanently mid-answer, which the real one is
/// never permanently in: `SettingGuard.warmKey()` makes exactly one round trip
/// and `SealKeyCache` keeps what it brings back.
///
/// Nothing was vacuous while the page did nothing with the answer. Since
/// `readTheStoredPolicy` re-decides the list, a fixture that can never answer is
/// a fixture in which that never runs — so this is the claim the shared fixture
/// now has to keep, asserted where the fixture is, rather than only inside the
/// one test that builds its own ports.
@MainActor
final class TheSharedPageOpensOnWhatIsStoredTests: XCTestCase {

    /// A store as an earlier run of the app would have left it: the policy the
    /// person chose, sealed. `PlantedSealKey`'s material is fixed, so the seal
    /// written here is one the page's own guard accepts — the same key, not the
    /// same object.
    private func storeHolding(_ policy: KeepPolicy) -> NamespacedStore {
        let store = duplicatesStore(folder: "\(home)/Downloads")
        DuplicatesSettings.setKeepPolicy(policy, in: store,
                                         guardedBy: SettingGuard(keys: PlantedSealKey()))
        return store
    }

    func testThePageOpensOnTheStoredPolicyRatherThanTheDefault() async {
        let dvm = duplicatesModel(over: OneAnswerTransport(groups: []),
                                  store: storeHolding(.byDate))
        XCTAssertEqual(dvm.policy, .standard,
                       "precondition: the page starts on the default, before the read lands")

        await dvm.firstLoad?.value

        XCTAssertEqual(dvm.policy, .byDate, """
            the page never learned what was stored: the shared fixture's guard cannot go warm, \
            so `keepPolicyIfWarm` answers «not yet» for the life of the test
            """)
    }

    /// And the default is still the default — a fixture that answered `.byDate`
    /// to everything would pass the test above and mean nothing.
    func testAStoreWithNoPolicyLeavesThePageOnTheDefault() async {
        let dvm = duplicatesModel(over: OneAnswerTransport(groups: []))

        await dvm.firstLoad?.value

        XCTAssertEqual(dvm.policy, .standard)
    }
}
