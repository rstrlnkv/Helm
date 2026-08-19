import HelmContract
import HelmRuntime
import HelmUI
import XCTest
@testable import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The page is where the policy is chosen and the engine is where it is applied,
/// and between them sit a plist entry, a MAC and a wire — three places the answer
/// can be dropped without anything failing to build.
///
/// **The seal is the part a UI test has to prove.** The engine refuses a policy
/// it did not write (`TheKeepPolicyIsSealedWhereStoredTests`), so a page that
/// stores the value and forgets the MAC would leave every background scan on the
/// default while the popup on screen says otherwise — and the log line about a
/// tampered setting would be about the app's own writing.
@MainActor
final class ThePolicyOnScreenIsTheOneInForceTests: XCTestCase {

    private var store: NamespacedStore!
    private var keys: PlantedSealKey!
    /// The page's guard, wired the way the module wires it: behind
    /// `SealKeyCache`, because what the page reads it reads only once the key is
    /// in hand and a port that keeps nothing is never in hand
    /// (`ThePageNeverWaitsForTheKeychainTests`).
    private var settings: SettingGuard!

    override func setUp() async throws {
        store = duplicatesStore(folder: "\(home)/Downloads")
        keys = PlantedSealKey()
        settings = SettingGuard(keys: SealKeyCache(keys))
    }

    /// The page with its first load finished.
    ///
    /// **Awaited, not raced.** The policy arrives from a task the initialiser
    /// holds, because reading it goes to the keychain and this page is built on
    /// the thread that draws; a test that read `policy` on the next line would be
    /// asserting about a page mid-load rather than about what is in force.
    private func model(_ wire: EngineTransport = OneAnswerTransport(groups: [])) async
    -> DuplicatesViewModel {
        let dvm = DuplicatesViewModel(vm: ModuleViewModel(transport: wire), store: store,
                                      settings: settings)
        await dvm.firstLoad?.value
        return dvm
    }

    /// The whole crossing in one assertion: the page writes, the engine reads,
    /// and the engine is the one that judges the seal.
    func testChoosingAPolicyStoresItWhereTheEngineReadsIt() async {
        let dvm = await model()

        dvm.choose(.byDate)

        let engine = DuplicatesEngine(store: store, settings: SettingGuard(keys: keys))
        XCTAssertEqual(engine.storedKeepPolicy(), .byDate,
                       "the background scan reads what the page stored, seal and all")
    }

    /// And the value that is stored is what the popup opens on, so the sentence
    /// under the toolbar describes the search that is actually going to run.
    func testThePageOpensOnTheStoredPolicy() async {
        await model().choose(.byDate)

        let reopened = await model()

        XCTAssertEqual(reopened.policy, .byDate)
    }

    /// A Mac nobody has asked gets the standard belief, and the popup says so
    /// rather than showing an empty selection.
    func testAPageThatWasNeverAskedShowsTheStandardPolicy() async {
        let policy = await model().policy

        XCTAssertEqual(policy, .standard)
    }

    /// A stored policy Helm did not write is not the one the page shows either.
    /// The page and the engine must not disagree about a forged setting — the
    /// screen would then be the only place claiming the forged value is in force.
    ///
    /// **The forged value is the one that is not the default**, and it has to be:
    /// forging `byPlace` asserts that the answer is `byPlace`, which a page that
    /// reads the plist unchecked also satisfies. Measured — that shape passed
    /// with the seal skipped, exactly as `TheKeepPolicyIsSealedWhereStoredTests`
    /// records one target down.
    func testAForgedPolicyIsNotWhatThePageShows() async {
        // Sealed through the same call the page makes, so what is planted here is
        // what a person choosing `by place` would have left behind.
        DuplicatesSettings.setKeepPolicy(.byPlace, in: store,
                                         guardedBy: SettingGuard(keys: keys))
        store.set(KeepPolicy.byDate.rawValue, for: DuplicatesSettings.keepPolicyKey)

        let policy = await model().policy

        XCTAssertEqual(policy, .byPlace)
    }

    /// The request carries it, because the engine needs the policy *before* it
    /// hashes anything — the representative of a hard-linked set is chosen by
    /// the same ladder — and because the person may have just changed the popup.
    func testASearchCarriesThePolicyThePageIsShowing() async {
        let wire = DuplicatesWire(groups: [])
        let dvm = await model(wire)
        dvm.choose(.byDate)

        dvm.search()
        for _ in 0..<200 where dvm.phase != .result { await Task.yield() }

        XCTAssertEqual(wire.searches.map(\.keepPolicy), [.byDate],
                       "the search ran on whatever the engine had stored, not on the popup")
    }
}
