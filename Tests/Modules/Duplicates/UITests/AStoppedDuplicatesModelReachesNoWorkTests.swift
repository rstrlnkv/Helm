import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// After `stop()` a press on the page reaches no work, no search answer still in
/// flight is shown, and `appear()` asks the keychain nothing; saving a chosen
/// folder or policy still does, which `stop` does not refuse.
///
/// The host calls the descriptor's `stop(_:)` before the engine's `deactivate()`:
/// on the person's switch and on quit. A page still on screen (or a task already
/// queued) may press a control after that; a search, a removal or a background
/// scan sent to a deactivated engine is work nobody asked the module to do any
/// more. Each press below is counted at the fake, and the count before `stop()` is
/// the control that proves the fake would have counted it.
@MainActor
final class AStoppedDuplicatesModelReachesNoWorkTests: XCTestCase {

    private var survivor: String { "\(home)/Downloads/keep.bin" }
    private var extra: String { "\(home)/Downloads/extra.bin" }

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [.init(path: survivor, bytes: 9_000_000),
                                .init(path: extra, bytes: 9_000_000)])
    }

    private func count(_ call: Call, in work: AnsweringWork) -> Int {
        work.calls.filter { $0 == call }.count
    }

    func testAPressAfterStopReachesNoWork() async {
        let work = AnsweringWork(groups: [group])
        let dvm = await searchedModel(over: work)
        dvm.toggleBasket(extra)
        XCTAssertEqual(dvm.basket, [extra], "precondition: the extra is in the basket")
        await dvm.emptyBasket()
        _ = await dvm.backgroundScan()
        dvm.cancel()
        // A removal parked, so that Stop has something to stop.
        // The fake removes nothing, so the extra is still marked.
        XCTAssertEqual(dvm.basket, [extra], "precondition: the extra is still marked")
        work.answers(.park, to: .trash)
        let removal = Task { await dvm.emptyBasket() }
        for _ in 0..<1000 where work.parkedCount < 1 { await Task.yield() }
        dvm.stopRemoval()
        XCTAssertEqual(count(.find, in: work), 1, "control: the search reaches the work before stop()")
        XCTAssertEqual(count(.trash, in: work), 2, "control: the removal reaches the work before stop()")
        XCTAssertEqual(count(.backgroundScan, in: work), 1, "control: the background scan reaches the work before stop()")
        XCTAssertEqual(count(.cancel, in: work), 1, "control: Stop reaches the work before stop()")
        XCTAssertEqual(count(.stopRemoval, in: work), 1, "control: Stop removal reaches the work before stop()")

        // The removal is still in flight, so `busy` is what lets Stop removal
        // through; only the closed model can refuse it.
        XCTAssertTrue(dvm.busy, "precondition: a removal is running")
        let before = work.calls
        dvm.stop()
        dvm.stopRemoval()
        dvm.search()
        dvm.cancel()
        work.releaseParked()
        await removal.value
        XCTAssertEqual(dvm.basket, [extra], "precondition: something is marked to send")
        await dvm.emptyBasket()
        let report = await dvm.backgroundScan()
        await settle()

        XCTAssertNil(report)
        XCTAssertEqual(work.calls, before, "a call reached the work after stop()")
    }

    /// A search that was in flight when the module was switched off does not land
    /// on the page afterwards.
    func testAnAnswerAfterStopIsNotShown() async {
        let work = AnsweringWork(groups: [group], answering: .park)
        let dvm = duplicatesModel(over: work)
        dvm.search()
        for _ in 0..<1000 where work.parkedCount < 1 { await Task.yield() }
        XCTAssertEqual(work.parkedCount, 1, "precondition: the search is really in flight")

        dvm.stop()
        work.releaseParked()
        await settle()

        XCTAssertTrue(dvm.groups.isEmpty, "an answer landed on a stopped model")
        XCTAssertNotEqual(dvm.phase, .result)
    }

    /// `makeModule` builds the model when the module starts and the page asks the
    /// keychain when it first appears; a model that was stopped before that asks
    /// it nothing.
    func testAppearAfterStopAsksTheKeychainNothing() async {
        let probe = SealKeyProbe()
        let dvm = DuplicatesViewModel(work: AnsweringWork(groups: []),
                                      store: duplicatesStore(folder: "\(home)/Downloads"),
                                      settings: SettingGuard(keys: SealKeyCache(probe)))
        dvm.stop()
        dvm.appear()
        await dvm.firstLoad?.value
        await settle()
        XCTAssertEqual(probe.reads, 0, "a stopped model asked the keychain")

        let live = SealKeyProbe()
        let page = DuplicatesViewModel(work: AnsweringWork(groups: []),
                                       store: duplicatesStore(folder: "\(home)/Downloads"),
                                       settings: SettingGuard(keys: SealKeyCache(live)))
        XCTAssertEqual(live.reads, 0, "building the model asked the keychain")
        page.appear()
        await page.firstLoad?.value
        XCTAssertGreaterThan(live.reads, 0, "control: appear() asks the keychain while the model lives")
    }

    /// Dropping the module's parts drops the model: nothing the descriptor built
    /// holds it once `stop()` has run, so the groups a search left in it are freed.
    func testAStoppedModelIsReleasedWithItsParts() async {
        weak var released: DuplicatesViewModel?
        do {
            let dvm = await searchedModel(over: AnsweringWork(groups: [group]))
            released = dvm
            dvm.stop()
        }
        await settle()
        XCTAssertNil(released, "a stopped model is still held after its owner let go")
    }
}
