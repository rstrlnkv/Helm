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

    override func setUp() {
        super.setUp()
        store = duplicatesStore(folder: "\(home)/Downloads")
        keys = PlantedSealKey()
    }

    private func model(_ wire: EngineTransport = OneAnswerTransport(groups: []))
    -> DuplicatesViewModel {
        DuplicatesViewModel(vm: ModuleViewModel(transport: wire), store: store,
                            settings: SettingGuard(keys: keys))
    }

    /// The whole crossing in one assertion: the page writes, the engine reads,
    /// and the engine is the one that judges the seal.
    func testChoosingAPolicyStoresItWhereTheEngineReadsIt() {
        let dvm = model()

        dvm.choose(.byDate)

        let engine = DuplicatesEngine(store: store, settings: SettingGuard(keys: keys))
        XCTAssertEqual(engine.storedKeepPolicy(), .byDate,
                       "the background scan reads what the page stored, seal and all")
    }

    /// And the value that is stored is what the popup opens on, so the sentence
    /// under the toolbar describes the search that is actually going to run.
    func testThePageOpensOnTheStoredPolicy() {
        model().choose(.byDate)

        XCTAssertEqual(model().policy, .byDate)
    }

    /// A Mac nobody has asked gets the standard belief, and the popup says so
    /// rather than showing an empty selection.
    func testAPageThatWasNeverAskedShowsTheStandardPolicy() {
        XCTAssertEqual(model().policy, .standard)
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
    func testAForgedPolicyIsNotWhatThePageShows() {
        // Sealed through the same call the page makes, so what is planted here is
        // what a person choosing `by place` would have left behind.
        DuplicatesSettings.setKeepPolicy(.byPlace, in: store,
                                         guardedBy: SettingGuard(keys: keys))
        store.set(KeepPolicy.byDate.rawValue, for: DuplicatesSettings.keepPolicyKey)

        XCTAssertEqual(model().policy, .byPlace)
    }

    /// The request carries it, because the engine needs the policy *before* it
    /// hashes anything — the representative of a hard-linked set is chosen by
    /// the same ladder — and because the person may have just changed the popup.
    func testASearchCarriesThePolicyThePageIsShowing() async {
        let wire = DuplicatesWire(groups: [])
        let dvm = model(wire)
        dvm.choose(.byDate)

        dvm.search()
        for _ in 0..<200 where dvm.phase != .result { await Task.yield() }

        XCTAssertEqual(wire.searches.map(\.keepPolicy), [.byDate],
                       "the search ran on whatever the engine had stored, not on the popup")
    }
}
