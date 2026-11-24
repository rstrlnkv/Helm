import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// The close does not write the record `TrashOfferPlan.answered` refuses to
/// write. `trashOfferDismissed` is final while the app sits in the Trash, and
/// a refusal from macOS is not a decision; the close declines every group on
/// screen, and after a refusal its only button is «Done».
///
/// The tests drive what the close drives: `removeSelection()`, then `answered()`.
@MainActor
final class ARefusalIsNotADeclineAtTheCloseTests: XCTestCase {

    private func offer(_ id: String, matchedByName: Bool = false) -> TrashedAppLeftovers {
        TrashedAppLeftovers(
            bundleID: id, name: "Vendor Tool", appPath: "/Users/x/.Trash/\(id).app",
            leftovers: [Leftover(path: "\(NSHomeDirectory())/Library/Caches/\(id)",
                                 kind: .caches, sizeBytes: 2_048, matchedByName: matchedByName)])
    }

    private func opened(_ work: AnsweringWork) async -> TrashedLeftoversModel {
        let model = TrashedLeftoversModel(uvm: modelOver(work))
        await model.load()
        return model
    }

    /// The bundle ids written to the permanent record, in the order they were
    /// written.
    private func declined(_ work: AnsweringWork) -> [String] { work.dismissed }

    // MARK: -

    /// One app's files moved, the other's were refused by macOS; closing the
    /// report does not file the refused app as the person's own "no".
    func testAnAppMacOSRefusedIsNotDeclinedByClosingTheReport() async throws {
        let moved = offer("com.vendor.moved")
        let refused = offer("com.vendor.refused")
        let work = AnsweringWork(
            removal: UninstallResult(
                trashed: moved.leftovers.map(\.path), freedBytes: 2_048,
                failures: refused.leftovers.map {
                    TrashFailureInfo(path: $0.path, reason: .needsFullDiskAccess,
                                     message: "Operation not permitted")
                }),
            offers: [moved, refused])
        let model = await opened(work)
        XCTAssertEqual(model.groups.count, 2, "precondition: both apps are on screen")

        let mayClose = await model.removeSelection()

        XCTAssertFalse(mayClose, "precondition: a refusal keeps the window up to report it")
        XCTAssertEqual(declined(work), ["com.vendor.moved"], """
            precondition: the removal filed the app it answered for and only that one — \
            the subject of the assertion below has to have happened for its absence to \
            mean anything
            """)

        // The close. `TrashedLeftoversView.onDisappear` runs exactly this, and it
        // is reached by Done, by Escape and by the red button alike.
        await model.answered()

        XCTAssertFalse(declined(work).contains("com.vendor.refused"), """
            closing the report filed the app macOS refused as the person's own "no". That \
            record is final for as long as the app sits in the Trash, and this window is the \
            only place a Group Container or a name-matched folder is ever offered — so \
            granting Full Disk Access afterwards does not bring the offer back.
            """)
    }

    /// The half that must keep working: a window closed without a removal is a
    /// "no", and one not recorded comes back at the next launch.
    func testClosingWithoutARemovalStillDeclinesEveryAppOnScreen() async throws {
        let first = offer("com.vendor.one")
        let second = offer("com.vendor.two")
        let work = AnsweringWork(offers: [first, second])
        let model = await opened(work)

        await model.answered()

        XCTAssertEqual(Set(declined(work)), ["com.vendor.one", "com.vendor.two"],
                       "a window shut without an answer will open again at the next launch")
        XCTAssertTrue(work.batches.isEmpty,
                       "precondition: nothing was removed, so this is the plain no")
    }
}
