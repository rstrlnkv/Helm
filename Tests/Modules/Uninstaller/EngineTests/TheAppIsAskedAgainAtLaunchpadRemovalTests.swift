import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// **The door asks whether the app is up where it moves it, and again after the quit.**
///
/// The card's `running` is a reading from when it was drawn. An app started since, with no quit agreed,
/// holds the removal (`stillRunning`) and nothing moves — the bundle or its leftovers. With the quit
/// agreed, an app that ignores it is still up when the loop ends, and that is asked again: the answer
/// is `stillRunning` and nothing moves. It is `trashPaths`'s own rule (`TheAppIsAskedAgainAtRemovalTests`);
/// these hold that the door goes through it.
final class TheAppIsAskedAgainAtLaunchpadRemovalTests: XCTestCase {

    private var home: URL!
    private let toolID = "com.acme.tool"
    private var candidate: AppRemovalCandidate!
    private var cache: String!

    override func setUpWithError() throws {
        home = scratchDirectory("launchpad-running")
        let path = try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: toolID)
        candidate = AppRemovalCandidate(bundleID: toolID, path: path, name: "Tool")
        cache = try write("Library/Caches/\(toolID)/data", in: home, bytes: 16)
            .deletingLastPathComponent().path
    }

    private func engine(_ running: FakeRunning, trash: FakeTrash) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(), trash: trash, running: running)
    }

    func testAnAppThatIsUpAtTheActAndNotAllowedToQuitHoldsEverything() async {
        let trash = FakeTrash()
        let running = FakeRunning(running: [toolID])

        let report = await engine(running, trash: trash).removeApp(candidate, quittingIfRunning: false)

        XCTAssertEqual(report.outcome, .stillRunning)
        XCTAssertEqual(trash.trashed, [], "something moved while the app ran")
        XCTAssertEqual(running.quits.count, 0, "an app was quit without being agreed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache), "its leftovers went while it stayed")
    }

    func testAnAppThatIgnoresTheQuitIsAskedAgainAndHoldsEverything() async {
        let trash = FakeTrash()
        let running = FakeRunning(running: [toolID], stubborn: [toolID])

        let report = await engine(running, trash: trash).removeApp(candidate, quittingIfRunning: true)

        XCTAssertEqual(running.quits.map(\.0), [toolID], "precondition: the quit was asked")
        XCTAssertEqual(report.outcome, .stillRunning, "the answer to «still up after the quit» was not read")
        XCTAssertEqual(trash.trashed, [], "the bundle moved out from under a live process")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache))
    }

    /// The control: an app that goes when asked is moved with the rest.
    func testAnAppThatQuitsAsAskedMoves() async {
        let trash = FakeTrash()
        let running = FakeRunning(running: [toolID], quitAfter: 0.1)

        let door = engine(running, trash: trash)
        _ = await door.removalPreview(candidate)
        let report = await door.removeApp(candidate, quittingIfRunning: true)

        XCTAssertEqual(running.quits.map(\.1), [true])
        XCTAssertEqual(report.outcome, .moved)
        XCTAssertEqual(Set(trash.trashed), [candidate.path, cache])
    }

    func testThePreviewSaysTheAppIsUp() async {
        let preview = await engine(FakeRunning(running: [toolID]), trash: FakeTrash())
            .removalPreview(candidate)
        guard case .ready(let ready) = preview else { return XCTFail("a plain app was refused: \(preview)") }
        XCTAssertTrue(ready.running)
    }
}
