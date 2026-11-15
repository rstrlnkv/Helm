import HelmRuntime
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// «Choose another folder» during a removal ended in `search()`, which empties
/// the basket and the report the removal's tick and Stop button are drawn in,
/// and it stored the new folder with its seal while the request was still out.
/// The button is dimmed and `use(folder:)` refuses, like «Search again»
/// (`ASearchIsNotAWayOutOfARemovalTests`).
///
/// Parked, never answered on the spot: a removal that returns before the press
/// is a window nothing can be inside.
@MainActor
final class AFolderChangeIsNotAWayOutOfARemovalTests: XCTestCase {

    private var extra: String { "\(home)/Downloads/extra.bin" }

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [.init(path: "\(home)/Downloads/keep.bin", bytes: 9_000_000),
                                .init(path: extra, bytes: 9_000_000)])
    }

    func testAFolderChosenWhileTheFilesAreGoingChangesNothing() async {
        let work = AnsweringWork(groups: [group],
                                  removal: DuplicateRemoval(removed: [extra], refused: [],
                                                            freedBytes: 9_000_000))
        let store = duplicatesStore(folder: "/some/folder")
        let dvm = duplicatesModel(over: work, store: store)
        dvm.search()
        await waitUntil("dvm.phase == .result", within: .seconds(5)) { dvm.phase == .result }
        dvm.toggleBasket(extra)
        work.answers(.park, to: .trash)
        Task { await dvm.emptyBasket() }
        await waitUntil("work.parkedCount >= 1", within: .seconds(5)) { work.parkedCount >= 1 }
        XCTAssertTrue(dvm.busy, "precondition: the removal is really in flight")
        let findsBefore = work.calls.filter { $0 == .find }.count
        let folderBefore = dvm.folder
        let macBefore = store.string("folderMAC", default: "")
        let chosen = URL(fileURLWithPath: home).appendingPathComponent("Pictures")

        dvm.use(folder: chosen)

        XCTAssertEqual(dvm.folder, folderBefore, "the page's folder moved during a removal")
        XCTAssertEqual(store.string("folder", default: ""), "/some/folder")
        XCTAssertEqual(store.string("folderMAC", default: ""), macBefore)
        XCTAssertEqual(work.calls.filter { $0 == .find }.count, findsBefore,
                       "a search was started during a removal")

        work.answers(.reply)
        work.releaseParked()
        await waitUntil("!dvm.busy", within: .seconds(5)) { !dvm.busy }
        XCTAssertFalse(dvm.busy, "precondition: the removal answered")

        dvm.use(folder: chosen)
        await waitUntil("a new find was asked for", within: .seconds(5)) { work.calls.filter({ $0 == .find }).count != findsBefore }

        XCTAssertEqual(dvm.folder, chosen, "control: once the removal is over the folder changes")
        XCTAssertEqual(store.string("folder", default: ""), chosen.path)
        XCTAssertGreaterThan(work.calls.filter { $0 == .find }.count, findsBefore)
    }

    /// The press itself, not only what it ends in: `chooseFolder()` is the
    /// button's action, and during a removal it must not put the panel up at all
    /// (a panel answered after the removal began is a folder the guard in
    /// `use(folder:)` then refuses, after the person has been asked).
    func testTheFolderPanelIsNotOpenedDuringARemoval() async {
        let work = AnsweringWork(groups: [group],
                                  removal: DuplicateRemoval(removed: [extra], refused: [],
                                                            freedBytes: 9_000_000))
        var asked = 0
        let dvm = duplicatesModel(over: work, chooseFolder: { asked += 1; return nil })
        dvm.search()
        await waitUntil("dvm.phase == .result", within: .seconds(5)) { dvm.phase == .result }
        dvm.toggleBasket(extra)
        work.answers(.park, to: .trash)
        Task { await dvm.emptyBasket() }
        await waitUntil("work.parkedCount >= 1", within: .seconds(5)) { work.parkedCount >= 1 }
        XCTAssertTrue(dvm.busy, "precondition: the removal is really in flight")

        dvm.chooseFolder()

        XCTAssertEqual(asked, 0, "the folder panel was put up during a removal")

        work.answers(.reply)
        work.releaseParked()
        await waitUntil("!dvm.busy", within: .seconds(5)) { !dvm.busy }
        XCTAssertFalse(dvm.busy, "precondition: the removal answered")

        dvm.chooseFolder()

        XCTAssertEqual(asked, 1, "control: once the removal is over the press asks")
    }
}
