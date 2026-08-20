import HelmTestSupport
import XCTest

/// **The Leftovers tab starts a removal from a `@State` flag with nothing
/// standing beside the request.**
///
/// «The model refuses; the page dims. Both, or neither is reliable» —
/// ARCHITECTURE.md § One removal at a time. `OneRemovalAtATimeEverywhereTests`
/// (HelmAppTests) enforces it for every module by walking `Sources/Modules` for
/// files whose **name contains `ViewModel`**, and this module has three doors to
/// the Trash of which that finds one:
///
/// - `UninstallerViewModel.removeSelection` — found, and it has the guard;
/// - `TrashedLeftoversModel.removeSelection` — the unprompted window's own
///   model, which sends the command itself and is not called a view model;
///   `TheTrashOfferSendsOneBatchTests` drives that one against a transport that
///   does not answer until it is told to, which is the better proof and is
///   available because the model is reachable;
/// - `OrphansView.trashSelected` — this one, whose `busy` is a `@State` on the
///   view. It is reachable by no test at all: a `@State` inside a `View` struct
///   has no seam, and the press that starts it comes out of a
///   `confirmationDialog`. Reading the source is what is left.
///
/// What a second press costs is not a second deletion — the files are already in
/// the Trash. It is a **wrong report about the first**: every path comes back
/// refused, and `trashSelected` writes `failures`, `removedCount` and `banner`
/// from whichever round answers last.
final class TheOrphansTabRefusesASecondPressTests: XCTestCase {

    func testTheOrphansTabRefusesASecondRemoval() throws {
        // `RepoSource.root` rather than a count of parent directories, which is a
        // fact about where this file sits and breaks silently when it moves
        // (CLAUDE.md § Test plumbing).
        let view = RepoSource.root
            .appendingPathComponent("Sources/Modules/Uninstaller/UI/OrphansView.swift")
        let source = try String(contentsOf: view, encoding: .utf8)

        // The hazard first, the guard second. A test that only asks for the
        // guard passes the day the subject stops existing, and it should say so
        // instead: if this page no longer starts a removal of its own — because
        // the request moved behind the view model, which is the other repair —
        // then this test has outlived its subject and goes with it.
        XCTAssertTrue(source.contains("uvm.trashPaths"),
                      "OrphansView no longer sends a batch to the Trash itself. If the "
                      + "removal moved behind the view model, which already refuses a "
                      + "second run, delete this test rather than weakening it.")
        XCTAssertTrue(source.contains("guard !busy"), """
            the Leftovers tab can start a second removal while the first is still running: \
            `busy` is a `@State` the footer reads, and `trashSelected` sets it without ever \
            asking. `OneRemovalAtATimeEverywhereTests` does not see this file — it matches \
            on names containing «ViewModel» — and no behavioural test can reach it, because \
            a `@State` in a `View` has no seam.
            """)
    }
}
