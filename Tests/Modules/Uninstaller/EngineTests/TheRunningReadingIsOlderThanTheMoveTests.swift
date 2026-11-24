import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// A reading of which applications are up is not good for the move.
///
/// `trashPaths` quits a batch's running applications in turn, then asks again,
/// and `held()` returns what is still up as `stillRunning`. These tests hold
/// that second asking, against the two ordinary ways an app is up when its
/// bundle moves:
///
/// - it came back while the batch was quitting the others (a login item, a
///   helper, the person double-clicking);
/// - it ignored the quit, and the deadline ended the wait
///   (Architecture/Uninstaller.md § Uninstaller).
///
/// macOS moves a running app's bundle without complaint, so without the second
/// asking the half-uninstall would be reported as a clean one. Any way out
/// (refusing the bundle, `stillRunning`, a failure) satisfies these tests; a
/// silent success does not.
final class TheRunningReadingIsOlderThanTheMoveTests: XCTestCase {

    private var home: URL!
    private let playerID = "com.acme.player"
    private let editorID = "com.acme.editor"

    override func setUpWithError() throws {
        // `RemovableScope` refuses everything outside a home, and the test keeps the gate.
        home = scratchDirectory("stale-running")
    }

    /// A bundle that answers the question production asks of it: the engine
    /// reads the id out of the bundle's own `Info.plist`.
    private func appBundle(_ name: String, id: String) throws -> String {
        let app = home.appendingPathComponent("Applications/\(name).app")
        _ = try write("Applications/\(name).app/Contents/MacOS/\(name)", in: home, bytes: 64)
        return try writeAppBundle(app, id: id)
    }

    private func engine(_ running: FakeRunning, trash: TrashPort) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(),
                          trash: trash, running: running)
    }

    // MARK: -

    /// An app that came back up while the batch was quitting the next one keeps
    /// its bundle: something can start an application without asking Helm
    /// (Architecture/TheGates.md § The gates).
    ///
    /// The moment is pinned, not timed: quitting the second app brings the first
    /// back, as a helper restarting its app does.
    func testAnAppThatCameBackUpWhileTheBatchQuitTheOthersKeepsItsBundle() async throws {
        let player = try appBundle("Player", id: playerID)
        let editor = try appBundle("Editor", id: editorID)
        let running = FakeRunning(running: [playerID, editorID], relaunching: [editorID: playerID])
        let trash = WatchfulTrash { [running] in running.isRunning(bundleID: "com.acme.player") }

        let result = await engine(running, trash: trash)
            .trashPaths([player, editor], quittingRunningApps: true)

        XCTAssertEqual(running.quits.map(\.0).sorted(), [editorID, playerID],
                       "precondition: both apps were asked to quit")
        XCTAssertTrue(running.isRunning(bundleID: playerID),
                      "precondition: the first app is up again by the time anything moves — "
                      + "without that this test passes with no re-reading at all")

        // `nil` — the bundle was never reached — is the other way out and passes
        // here: what must not happen is the move landing while the app is up.
        let atThePlayersMove = trash.atEachMove.first { $0.path == player }
        XCTAssertNotEqual(atThePlayersMove?.answer, true, """
            the bundle of a running app was moved out from under the process. It carries on \
            from where the bundle went and writes its preferences when it finally exits, so \
            the leftovers this batch has just taken come back — the half-uninstall \
            `waitUntilGone` exists to prevent, from a reading taken before the quitting started.
            """)
        XCTAssertFalse(result.trashed.contains(player)
                       && result.stillRunning.isEmpty && result.failures.isEmpty, """
            and the batch reported an unqualified success for it: `trashed` holds the bundle, \
            nothing is in `stillRunning`, nothing failed. Every screen this result reaches \
            says the app was removed.
            """)
    }

    /// An app that ignored the force quit is not reported as removed cleanly
    /// (Architecture/Uninstaller.md § Uninstaller).
    ///
    /// It costs the engine's own five-second deadline, the one that ships:
    /// `trashPaths` calls `waitUntilGone` with its defaults.
    func testAnAppThatIgnoredTheQuitIsNotReportedAsRemovedCleanly() async throws {
        let player = try appBundle("Player", id: playerID)
        let running = FakeRunning(running: [playerID], stubborn: [playerID])
        let trash = WatchfulTrash { [running] in running.isRunning(bundleID: "com.acme.player") }

        let result = await engine(running, trash: trash)
            .trashPaths([player], quittingRunningApps: true)

        XCTAssertEqual(running.quits.map(\.1), [true],
                       "precondition: the app was force quit, which is what the person ticked")
        XCTAssertTrue(running.isRunning(bundleID: playerID),
                      "precondition: it ignored the request, so the deadline is what ended "
                      + "the wait — the subject of this test")
        XCTAssertFalse(result.trashed.contains(player)
                       && result.stillRunning.isEmpty && result.failures.isEmpty, """
            an app that ignored a force quit had its bundle moved and the removal reported \
            itself clean: nothing in the result says the process is still running out of a \
            bundle that has moved, so the person is told the uninstall worked and the \
            preferences it removed come back when the app finally exits.
            """)
    }

    /// The control: without it, an engine that refused every batch would pass
    /// both tests above.
    func testAnAppThatReallyQuitStillMovesAndReportsItself() async throws {
        let player = try appBundle("Player", id: playerID)
        // Not zero: an app that vanishes the instant it is asked makes a test of
        // the wait vacuous.
        let running = FakeRunning(running: [playerID], quitAfter: 0.15)
        let trash = WatchfulTrash { [running] in running.isRunning(bundleID: "com.acme.player") }

        let result = await engine(running, trash: trash)
            .trashPaths([player], quittingRunningApps: true)

        XCTAssertEqual(result.trashed, [player],
                       "an app that quit as asked was refused its own removal")
        XCTAssertEqual(result.stillRunning, [], "and was reported as blocking the batch")
        XCTAssertEqual(trash.atEachMove.map(\.answer), [false],
                       "precondition: it really was gone by the time the bundle moved")
    }
}
