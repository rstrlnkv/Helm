import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// A `TrashPort` that answers a question at the moment of the move.
///
/// The subject is when the bundle goes: a wait that returned early and no wait
/// look identical in the result. So the double reads the world as it moves
/// each path and keeps the reading.
final class WatchfulTrash: TrashPort, @unchecked Sendable {
    private let lock = NSLock()
    private let watching: @Sendable () -> Bool
    private var readings: [(path: String, answer: Bool)] = []

    init(watching: @escaping @Sendable () -> Bool) { self.watching = watching }

    /// What the question answered as each path was moved, in order.
    var atEachMove: [(path: String, answer: Bool)] {
        lock.lock(); defer { lock.unlock() }; return readings
    }

    func trashItem(_ url: URL) -> TrashOutcome {
        let answer = watching()
        lock.lock(); readings.append((url.path, answer)); lock.unlock()
        // Gone from its place, as a real move leaves it: `HelmTrash.remove` asks.
        try? FileManager.default.removeItem(at: url)
        return .success
    }
}

/// The app is asked whether it is running where the answer is used, not from
/// `ScanResult.runningNow`, read when the review was built. An app relaunched
/// while the person reads the review must keep its bundle: macOS moves it
/// anyway, and the process writes the removed leftovers back on exit.
final class TheAppIsAskedAgainAtRemovalTests: XCTestCase {

    private var home: URL!
    private let playerID = "com.acme.player"

    override func setUpWithError() throws {
        // `RemovableScope` refuses everything outside a home, and the test keeps the gate.
        home = scratchDirectory("unrunning")
    }

    /// A bundle that answers the question production asks of it: the engine reads
    /// the id out of the bundle's own `Info.plist`.
    @discardableResult
    private func appBundle(_ name: String, id: String) throws -> String {
        let app = home.appendingPathComponent("Applications/\(name).app")
        _ = try write("Applications/\(name).app/Contents/MacOS/\(name)", in: home, bytes: 64)
        return try writeAppBundle(app, id: id)
    }

    private func leftover(_ name: String) throws -> String {
        try write("Library/Caches/\(name)", in: home, bytes: 32).path
    }

    private func engine(_ running: FakeRunning, trash: TrashPort) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(),
                          trash: trash, running: running)
    }

    // MARK: -

    /// The measured case: down at the scan, up at the press.
    func testAnAppThatCameBackUpAfterTheReviewKeepsItsBundle() async throws {
        let app = try appBundle("Player", id: playerID)
        let cache = try leftover("com.acme.player")
        // Down when the review was built — which is what the review's `running`
        // flag still says — and up by the time anybody presses anything.
        let running = FakeRunning(running: [])
        let trash = WatchfulTrash { true }
        running.launch(playerID)

        let result = await engine(running, trash: trash)
            .trashPaths([app, cache], quittingRunningApps: false)

        XCTAssertEqual(trash.atEachMove.map(\.path), [],
                       "the bundle of a running app was moved out from under the process, "
                       + "which writes its preferences back on exit")
        XCTAssertEqual(result.trashed, [], "and the batch reported moving it")
        XCTAssertEqual(result.stillRunning, [app],
                       "nothing said which app stopped the batch, so the screen has nothing "
                       + "to offer the person")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache),
                      "the leftovers of a running app went while the app stayed — a "
                      + "half-uninstall that the app itself undoes on exit")
    }

    /// Ticked «Force quit and remove anyway»: the bundle waits for the app to be
    /// gone. `quitAfter` keeps this from passing with the wait deleted.
    func testAnAllowedQuitIsWaitedForBeforeTheBundleMoves() async throws {
        let app = try appBundle("Player", id: playerID)
        let running = FakeRunning(running: [playerID], quitAfter: 0.15)
        let trash = WatchfulTrash { [running] in running.isRunning(bundleID: "com.acme.player") }

        let result = await engine(running, trash: trash).trashPaths([app],
                                                                    quittingRunningApps: true)

        XCTAssertEqual(running.quits.map(\.0), [playerID],
                       "the app was never asked to quit, so its bundle moved while it ran")
        XCTAssertEqual(running.quits.map(\.1), [true], "and it was asked politely")
        XCTAssertEqual(trash.atEachMove.map(\.answer), [false],
                       "the bundle moved while the app was still running: the wait came back "
                       + "early, or was never made")
        XCTAssertEqual(result.trashed, [app], "and then it did not move at all")
        XCTAssertEqual(result.stillRunning, [],
                       "an app that was quit as asked was reported as blocking the batch")
    }

    /// The control: an app that is down at the press moves, whatever the review
    /// thought, or "refuse everything" would pass the test above.
    func testAnAppThatIsDownAtThePressMovesWithNoPermissionAsked() async throws {
        let app = try appBundle("Player", id: playerID)
        let running = FakeRunning(running: [playerID])
        let trash = WatchfulTrash { true }
        // The person quit it themselves while reading the review.
        running.quit(bundleID: playerID, force: false)

        let result = await engine(running, trash: trash)
            .trashPaths([app], quittingRunningApps: false)

        XCTAssertEqual(result.trashed, [app],
                       "an app the person closed themselves stayed unremovable")
        XCTAssertEqual(result.stillRunning, [])
    }

    /// A batch with no application in it — the orphans screen, and the window
    /// that offers to clean up after an app already in the Trash — asks nobody
    /// anything.
    func testABatchOfLeftoversAloneIsNotHeldUpByAnythingRunning() async throws {
        let cache = try leftover("com.acme.player")
        let running = FakeRunning(running: [playerID])
        let trash = WatchfulTrash { true }

        let result = await engine(running, trash: trash).trashPaths([cache])

        XCTAssertEqual(result.trashed, [cache],
                       "a batch holding no app bundle was refused over an app that is running")
        XCTAssertEqual(running.quits.count, 0, "and nothing was asked to quit")
    }
}
