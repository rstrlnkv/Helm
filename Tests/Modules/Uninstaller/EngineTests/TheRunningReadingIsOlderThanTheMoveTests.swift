import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// **A reading of which applications are up is not good for the move.**
///
/// `removeBatch` quits the running applications of a batch one after another, a
/// force quit and a `waitUntilGone` per app, five seconds apiece by default,
/// before `trashSync` moves anything. After that loop it asks again, and
/// `held()` returns what is still up as `stillRunning` instead of moving it.
/// These tests hold that second asking; the first reading, taken at the top, is
/// older than the move by the length of the loop.
///
/// Two ways an application is up when its bundle moves, both of them ordinary:
///
/// - it came back while the batch was quitting the *others* — a login item, a
///   helper that restarts its app, `open -a`, or the person double-clicking;
/// - it ignored the quit, and the deadline ended the wait.
///
/// The second is the one already decided in ARCHITECTURE.md § Uninstaller:
/// «the deadline ends the *wait* rather than the question».
/// Without the second asking, nothing would answer either. macOS lets a running
/// app's bundle be moved, so nothing would refuse, nothing would be reported,
/// and the result would be an unqualified success — `trashed` holding the
/// bundle, `stillRunning` empty, `failures` empty. The process carries on out
/// of the moved bundle and writes its preferences when it finally exits, so the
/// leftovers this batch has just taken come back. That is the half-uninstall
/// `waitUntilGone` exists to prevent, reported as a clean one.
///
/// These tests do not prescribe which way out is taken. Refusing the bundle,
/// naming the app in `stillRunning`, or classifying it as a failure would each
/// satisfy them; a silent success does not.
final class TheRunningReadingIsOlderThanTheMoveTests: XCTestCase {

    private var home: URL!
    private let playerID = "com.acme.player"
    private let editorID = "com.acme.editor"

    override func setUpWithError() throws {
        // `RemovableScope` refuses everything outside a home, and a test exempted
        // from that gate is a test of a different program.
        home = scratchDirectory("stale-running")
    }

    /// A bundle that answers the question production asks of it: the engine
    /// reads the id out of the bundle's own `Info.plist`.
    private func appBundle(_ name: String, id: String) throws -> String {
        let app = home.appendingPathComponent("Applications/\(name).app")
        _ = try write("Applications/\(name).app/Contents/MacOS/\(name)", in: home, bytes: 64)
        try (["CFBundleIdentifier": id] as NSDictionary)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app.path
    }

    private func engine(_ running: FakeRunning, trash: TrashPort) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(),
                          trash: trash, running: running)
    }

    // MARK: -

    /// **An app that came back up while the batch was quitting the next one.**
    ///
    /// Two applications ticked together is the ordinary shape of this screen, and
    /// the batch quits them in turn. Nothing asks again about the first once its
    /// wait has come back, so anything that starts it in the seconds that follow
    /// — and something starting an application without asking Helm is the whole
    /// point of the family CLAUDE.md names — has its bundle taken out from under
    /// it.
    ///
    /// The moment is pinned rather than timed: `FakeRunning` is told that quitting
    /// the second app brings the first back, which is a helper restarting its own
    /// app and is deterministic in a way a `sleep` racing a deadline is not.
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

    /// **An app that ignored the force quit.**
    ///
    /// The deadline ending the wait, not the question, is a decision
    /// (ARCHITECTURE.md § Uninstaller); without the second asking nothing refuses
    /// to move, so the person is told the uninstall worked.
    ///
    /// It costs the engine's own five-second deadline, which is the number that
    /// ships: `removeBatch` calls `waitUntilGone` with its defaults and there is
    /// nothing to inject. A shorter one here would be a test of a different
    /// program.
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

    /// The control, and it is not decoration: without it, an engine that refused
    /// every batch would pass both tests above.
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
