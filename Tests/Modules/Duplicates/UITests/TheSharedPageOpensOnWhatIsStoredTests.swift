import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The fixture every page test in this target is built on can finish its read.
///
/// A bare `SealKeyProbe` takes `SealKeyPort`'s default `keyIfWarm() -> nil`, so
/// `SettingGuard.isWarm` stays false, `DuplicatesSettings.keepPolicyIfWarm`
/// answers «not yet» whatever is stored, and the popup sits on the default for
/// ever. The real keychain is never permanently mid-answer:
/// `SettingGuard.warmKey()` makes one round trip and `SealKeyCache` keeps what
/// it brings back.
///
/// `readTheStoredPolicy` re-decides the list, so a fixture that can never answer
/// is one in which that never runs; the claim is asserted where the fixture is.
@MainActor
final class TheSharedPageOpensOnWhatIsStoredTests: XCTestCase {

    /// A store as an earlier run of the app would have left it: the policy the
    /// person chose, sealed. `SealKeyProbe`'s material is fixed, so the seal
    /// written here is one the page's own guard accepts — the same key, not the
    /// same object.
    private func storeHolding(_ policy: KeepPolicy) -> NamespacedStore {
        let store = duplicatesStore(folder: "\(home)/Downloads")
        DuplicatesSettings.setKeepPolicy(policy, in: store,
                                         guardedBy: SettingGuard(keys: SealKeyProbe(firstUse: false)))
        return store
    }

    func testThePageOpensOnTheStoredPolicyRatherThanTheDefault() async {
        let dvm = duplicatesModel(over: AnsweringWork(groups: []),
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
        let dvm = duplicatesModel(over: AnsweringWork(groups: []))

        await dvm.firstLoad?.value

        XCTAssertEqual(dvm.policy, .standard)
    }
}
