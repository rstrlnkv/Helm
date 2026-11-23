import HelmContract
import HelmRuntime
import HelmUI
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


    private func count(_ call: Call, in work: AnsweringWork) -> Int {
        work.calls.filter { $0 == call }.count
    }

    /// The descriptor's pass-on, which the model's own `backgroundScan` does not
    /// prove: a descriptor without the override falls to the protocol default,
    /// which answers nil, and the coordinator then logs «no answer» every tick.
    func testTheDescriptorPassesTheScanOn() async {
        let work = AnsweringWork(groups: [])
        let parts = ModuleParts(engine: NoEngine(), model: DuplicatesViewModel(work: work, store: duplicatesStore(folder: "\(home)/Downloads"),
                                                                               settings: SettingGuard(keys: SealKeyCache(SealKeyProbe())),
                                                                               chooseFolder: { nil }))
        let report = await DuplicatesDescriptor().backgroundScan(parts)
        XCTAssertNotNil(report, "the descriptor fell to the default: «no answer» every tick")
        XCTAssertEqual(count(.backgroundScan, in: work), 1)
    }

    private final class NoEngine: ModuleEngine { func activate() {}; func deactivate() {} }

    func testAPressAfterStopReachesNoWork() async {
        let work = AnsweringWork(groups: [keepAndExtra()])
        let dvm = await searchedModel(over: work)
        dvm.toggleBasket(extraCopy)
        XCTAssertEqual(dvm.basket, [extraCopy], "precondition: the extra is in the basket")
        await dvm.emptyBasket()
        _ = await dvm.backgroundScan()
        dvm.cancel()
        // A removal parked, so that Stop has something to stop.
        // The fake removes nothing, so the extra is still marked.
        XCTAssertEqual(dvm.basket, [extraCopy], "precondition: the extra is still marked")
        work.answers(.park, to: .trash)
        let removal = Task { await dvm.emptyBasket() }
        await waitUntil("work.parkedCount >= 1", within: .seconds(5)) { work.parkedCount >= 1 }
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
        XCTAssertEqual(dvm.basket, [extraCopy], "precondition: something is marked to send")
        await dvm.emptyBasket()
        let report = await dvm.backgroundScan()
        await grace()

        XCTAssertNil(report)
        XCTAssertEqual(work.calls, before, "a call reached the work after stop()")
    }

    /// A search that was in flight when the module was switched off does not land
    /// on the page afterwards.
    func testAnAnswerAfterStopIsNotShown() async {
        let work = AnsweringWork(groups: [keepAndExtra()], answering: .park)
        let dvm = duplicatesModel(over: work)
        dvm.search()
        await waitUntil("work.parkedCount >= 1", within: .seconds(5)) { work.parkedCount >= 1 }
        XCTAssertEqual(work.parkedCount, 1, "precondition: the search is really in flight")

        dvm.stop()
        work.releaseParked()
        await grace()

        XCTAssertTrue(dvm.groups.isEmpty, "an answer landed on a stopped model")
        XCTAssertNotEqual(dvm.phase, .result)
    }

    /// The search `stop()` drops can never answer, so nothing else would take
    /// the phase off «Searching»: a model stopped mid-search kept saying so, and
    /// a page that outlived the stop (or a switch back on, which builds a new
    /// model but not a new page) drew a search nobody was running. Nothing
    /// visible changes today, because a stopped model is never drawn.
    func testAStoppedModelIsNotLeftSearching() async {
        let work = AnsweringWork(groups: [keepAndExtra()], answering: .park)
        let dvm = duplicatesModel(over: work)
        dvm.search()
        await waitUntil("work.parkedCount >= 1", within: .seconds(5)) { work.parkedCount >= 1 }
        XCTAssertEqual(dvm.phase, .searching, "precondition: the search is really in flight")

        dvm.stop()
        work.releaseParked()

        XCTAssertEqual(dvm.phase, .start, "a stopped model still says it is searching")
    }

    /// `makeModule` builds the model when the module starts and the page asks the
    /// keychain when it first appears; a model that was stopped before that asks
    /// it nothing.
    func testAppearAfterStopAsksTheKeychainNothing() async {
        let probe = SealKeyProbe()
        let dvm = DuplicatesViewModel(work: AnsweringWork(groups: []),
                                      store: duplicatesStore(folder: "\(home)/Downloads"),
                                      settings: SettingGuard(keys: SealKeyCache(probe)),
                                      chooseFolder: { nil })
        dvm.stop()
        dvm.appear()
        await dvm.firstLoad?.value
        await grace()
        XCTAssertEqual(probe.reads, 0, "a stopped model asked the keychain")

        let live = SealKeyProbe()
        let page = DuplicatesViewModel(work: AnsweringWork(groups: []),
                                       store: duplicatesStore(folder: "\(home)/Downloads"),
                                       settings: SettingGuard(keys: SealKeyCache(live)),
                                       chooseFolder: { nil })
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
            let dvm = await searchedModel(over: AnsweringWork(groups: [keepAndExtra()]))
            released = dvm
            dvm.stop()
        }
        await grace()
        XCTAssertNil(released, "a stopped model is still held after its owner let go")
    }
}
