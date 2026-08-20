import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The policy arrives from the keychain **after** the page is up, and the list
/// it lands on is not re-decided.
///
/// `policy` is assigned in exactly two places. `choose(_:)` — the popup — stores
/// it, seals it and calls `rearrange()`. `readTheStoredPolicy()` — the tail of
/// `firstLoad` — assigns it and stops there. So a page that already has a list
/// on it when the keychain finally answers keeps the old order under the new
/// belief, which is this module's own named defect: «the screen said `by date`
/// while every search ran `by place`».
///
/// **The window is the keychain's, and it is the reason `firstLoad` exists at
/// all.** The bundle is ad-hoc signed, so `SecItemCopyMatching` is a modal
/// authorization dialog rather than data — `HelmApp_2026-08-19-235500_MacBook.hang`,
/// 19,09 s. That dialog belongs to SecurityAgent and the read is on a detached
/// task, so Helm's own window is live behind it: the folder is remembered, the
/// prominent «Search now» button is right there, and a small folder answers in
/// under a second. The reply's own guard cannot help — it compares the policy
/// the *request* carried against `policy`, and at that moment they are still the
/// same value.
///
/// Held on a gate rather than answered on the spot, because a keychain that
/// replies instantly is over before the search can be started and every
/// assertion here would hold with `firstLoad` deleted.
@MainActor
final class TheStoredPolicyLandsOnTheListTests: XCTestCase {

    private let downloaded = "\(home)/Downloads/photo.jpg"
    private let filed = "\(home)/Documents/Trips/photo.jpg"

    /// One group the two policies disagree about: the copy in Downloads arrived
    /// first, the copy in Documents was filed an hour later. By place the filed
    /// one stays; by date the download does.
    ///
    /// **Ordered by the policy the request will carry, through `SurvivingCopy`
    /// itself.** A search reply is ordered by the engine, and the engine orders
    /// it by the policy it was sent — `DuplicatesWire` answers one fixed
    /// arrangement whatever the request says, so a fixture that hands over some
    /// other order is answering for an engine that does not exist, and every
    /// assertion about the list being in step would then be about the fixture.
    private func group(orderedBy policy: KeepPolicy) -> DuplicateGroup {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let copies: [DuplicateGroup.Copy] = [
            .init(path: downloaded, bytes: 4_000_000, added: day),
            .init(path: filed, bytes: 4_000_000, added: day.addingTimeInterval(3600)),
        ]
        return DuplicateGroup(copies: SurvivingCopy.order(copies, by: KeepRule(policy)))
    }

    /// The invariant the whole page rests on: the first copy of a group is the
    /// one that stays, and the popup above it says which copy that is. Asked of
    /// the model's own published values, so it is the question the header, the
    /// badge, the checkboxes and `emptyBasket` all read.
    private func firstRowIsWhatThePolicyKeeps(_ dvm: DuplicatesViewModel) -> Bool {
        dvm.groups.allSatisfy { group in
            SurvivingCopy.order(group.copies, by: KeepRule(dvm.policy)).first?.path
                == group.copies.first?.path
        }
    }

    /// A page whose store holds a sealed `by date`, and whose own read of it is
    /// parked until `gate` is signalled.
    ///
    /// Two `SealKeyCache`s over one probe, the arrangement
    /// `ThePageNeverWaitsForTheKeychainTests` uses: the seal is written through a
    /// cache of its own, so the page's cache is genuinely cold when it is built.
    private func pageWaitingForItsPolicy(_ wire: DuplicatesWire, gate: DispatchSemaphore)
    -> DuplicatesViewModel {
        let probe = SealKeyProbe(gate: gate)
        let store = duplicatesStore(folder: "\(home)/Downloads")
        // One signal spent here, sealing what the person chose on an earlier run.
        gate.signal()
        DuplicatesSettings.setKeepPolicy(.byDate, in: store, guardedBy: SettingGuard(keys: probe))
        return DuplicatesViewModel(vm: ModuleViewModel(transport: wire), store: store,
                                   settings: SettingGuard(keys: SealKeyCache(probe)))
    }

    /// The control, and it has to pass: with the keychain answering before the
    /// search, the page searches `by date`, the engine answers in that order and
    /// the two are in step. A failure below is about the late arrival and not
    /// about the fixture.
    func testAPolicyInHandBeforeTheSearchIsInStepWithTheList() async {
        let gate = DispatchSemaphore(value: 0)
        let wire = DuplicatesWire(groups: [group(orderedBy: .byDate)])
        let dvm = pageWaitingForItsPolicy(wire, gate: gate)
        gate.signal()
        await dvm.firstLoad?.value
        XCTAssertEqual(dvm.policy, .byDate, "precondition: the stored belief arrived first")

        dvm.search()
        for _ in 0..<1000 where dvm.phase != .result { await Task.yield() }

        XCTAssertEqual(wire.searches.map(\.keepPolicy), [.byDate],
                       "precondition: the request carried what the page was showing")
        XCTAssertTrue(firstRowIsWhatThePolicyKeeps(dvm))
    }

    /// And the same page when the keychain is still deciding while the search
    /// runs and answers: the list is `by place`, the popup then says `by date`,
    /// and nothing re-decides.
    func testAPolicyThatArrivesAfterTheSearchIsAppliedToTheList() async {
        let gate = DispatchSemaphore(value: 0)
        let wire = DuplicatesWire(groups: [group(orderedBy: .byPlace)])
        let dvm = pageWaitingForItsPolicy(wire, gate: gate)
        XCTAssertEqual(dvm.policy, .standard,
                       "precondition: the keychain has not answered, so the page holds the default")

        dvm.search()
        for _ in 0..<1000 where dvm.phase != .result { await Task.yield() }
        XCTAssertEqual(wire.searches.map(\.keepPolicy), [.byPlace],
                       "precondition: the search ran on the default, which is what the page had")
        XCTAssertEqual(dvm.groups.first?.paths.first, filed,
                       "precondition: the list is in the order `by place` asked for")

        // The keychain answers at last, twenty seconds into a page that has been
        // live throughout.
        gate.signal()
        await dvm.firstLoad?.value

        XCTAssertEqual(dvm.policy, .byDate,
                       "precondition: the stored belief did arrive, so the rest is about the list")
        XCTAssertTrue(firstRowIsWhatThePolicyKeeps(dvm), """
            the popup says `by date` and the list is still in `by place` order — the first row is \
            \(dvm.groups.first?.paths.first ?? "nothing") where the belief on screen keeps \
            \(downloaded). `readTheStoredPolicy` assigns `policy` and does not `rearrange()`, \
            which is the one thing `choose(_:)` does beside it
            """)
    }

    /// And the sentence beside the badge is the same disagreement said out loud:
    /// the header explains the copy the *ladder* would keep, and draws it against
    /// whichever copy is on the first row.
    func testTheHeaderExplainsTheCopyThatIsActuallyOnTheFirstRow() async throws {
        let gate = DispatchSemaphore(value: 0)
        let dvm = pageWaitingForItsPolicy(DuplicatesWire(groups: [group(orderedBy: .byPlace)]),
                                          gate: gate)
        dvm.search()
        for _ in 0..<1000 where dvm.phase != .result { await Task.yield() }
        gate.signal()
        await dvm.firstLoad?.value

        let shown = try XCTUnwrap(dvm.groups.first, "precondition: there is a list to explain")

        XCTAssertEqual(dvm.grounds(of: shown), .rung(.date), """
            precondition: the header is explaining a date, so the assertion below is about which \
            copy that sentence is drawn beside
            """)
        XCTAssertEqual(shown.copies.first?.path, downloaded, """
            «kept: arrived first» is drawn on the row holding \(filed), which arrived an hour \
            after the copy the sentence is about
            """)
    }
}
