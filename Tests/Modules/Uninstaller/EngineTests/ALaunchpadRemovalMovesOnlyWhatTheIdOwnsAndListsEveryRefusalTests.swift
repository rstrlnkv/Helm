import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// **The door takes what the Uninstaller's review ticks by default — the app and what is found under
/// its bundle id — and nothing a name merely resembles, and every refusal is in the report.**
///
/// A file named for the app (`Application Support/Tool`) is a guess; another app's id that starts with
/// this one's (`com.acme.toolbox`) is another app's. Neither is moved. A refusal by macOS is never
/// silent: it is a reason in `failed`, and a bundle that did not move is `refused`, not «moved with
/// failures» — the app is still installed.
final class ALaunchpadRemovalMovesOnlyWhatTheIdOwnsAndListsEveryRefusalTests: XCTestCase {

    private var home: URL!
    private let toolID = "com.acme.tool"
    private var candidate: AppRemovalCandidate!
    private var owned: String!
    private var guessed: String!
    private var neighbour: String!

    override func setUpWithError() throws {
        home = scratchDirectory("launchpad-moves")
        let path = try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: toolID)
        _ = try write("Applications/Tool.app/Contents/MacOS/Tool", in: home, bytes: 4_096)
        candidate = AppRemovalCandidate(bundleID: toolID, path: path, name: "Tool")
        owned = try write("Library/Caches/\(toolID)/data", in: home, bytes: 100)
            .deletingLastPathComponent().path
        guessed = try write("Library/Application Support/Tool/data", in: home, bytes: 100)
            .deletingLastPathComponent().path
        neighbour = try write("Library/Caches/\(toolID)box/data", in: home, bytes: 100)
            .deletingLastPathComponent().path
    }

    private func engine(trash: TrashPort, fs: FileSystemPort = FMFileSystem()) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(), fs: fs, trash: trash,
                          running: FakeRunning(running: []))
    }

    func testOnlyTheAppAndWhatItsIdOwnsMove() async {
        let trash = FakeTrash()
        let door = engine(trash: trash)
        _ = await door.removalPreview(candidate)

        let report = await door.removeApp(candidate, quittingIfRunning: false)

        XCTAssertEqual(report.outcome, .moved)
        XCTAssertEqual(Set(trash.trashed), [candidate.path, owned])
        XCTAssertTrue(FileManager.default.fileExists(atPath: guessed), "a folder named like the app was taken")
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighbour), "another app's folder was taken")
        XCTAssertGreaterThan(report.freedBytes, 0)
        XCTAssertEqual(report.failed, [])
    }

    func testThePreviewCountsWhatTheRemovalWouldTake() async {
        let ask = await engine(trash: FakeTrash()).removalPreview(candidate)

        guard case .ready(let preview) = ask else { return XCTFail("refused: \(ask)") }
        XCTAssertEqual(preview.leftoverCount, 1, "the guess or the neighbour was counted")
        XCTAssertGreaterThan(preview.leftoverBytes, 0)
        XCTAssertGreaterThan(preview.appBytes ?? 0, 0)
        XCTAssertFalse(preview.running)
    }

    func testALeftoverMacOSRefusesIsListedAndTheAppStillMoved() async {
        let trash = FakeTrash(failing: [owned])
        let door = engine(trash: trash)
        _ = await door.removalPreview(candidate)

        let report = await door.removeApp(candidate, quittingIfRunning: false)

        XCTAssertEqual(report.outcome, .movedWithFailures)
        XCTAssertEqual(report.failed.count, 1, "the refusal is in neither list")
        XCTAssertEqual(trash.trashed, [candidate.path])
    }

    func testABundleMacOSRefusesIsRefusedNotMoved() async {
        let trash = FakeTrash(failing: [candidate.path])
        let door = engine(trash: trash)
        _ = await door.removalPreview(candidate)

        let report = await door.removeApp(candidate, quittingIfRunning: false)

        XCTAssertEqual(report.outcome, .refused, "an app that is still installed was reported as moved")
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertEqual(trash.trashed, [], "the leftovers went to the Trash while the app stayed installed")
    }

    /// Only what the card counted: a folder that appears after the preview is not on it.
    func testNothingThatAppearedAfterTheCardIsTaken() async throws {
        let trash = FakeTrash()
        let door = engine(trash: trash)
        _ = await door.removalPreview(candidate)
        let late = try write("Library/Application Support/\(toolID)/data", in: home, bytes: 100)
            .deletingLastPathComponent().path

        let report = await door.removeApp(candidate, quittingIfRunning: false)

        XCTAssertEqual(report.outcome, .moved)
        XCTAssertEqual(Set(trash.trashed), [candidate.path, owned])
        XCTAssertTrue(FileManager.default.fileExists(atPath: late), "a leftover nobody previewed was taken")
    }

    /// A walk that does not finish in time is «no size», not a wrong one and not a wait.
    func testASizeThatIsNotMeasuredInTimeIsNilAndTheCardDoesNotWait() async {
        let slow = SlowBundle(path: candidate.path, delay: 1.0)
        let started = Date()

        let ask = await engine(trash: FakeTrash(), fs: slow).removalPreview(candidate, sizeDeadline: 0.1)

        guard case .ready(let preview) = ask else { return XCTFail("refused: \(ask)") }
        XCTAssertNil(preview.appBytes)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.8, "the preview waited for the walk")
    }
}

/// Every file measures as itself except the bundle, whose walk takes `delay`.
private struct SlowBundle: FileSystemPort {
    let path: String
    let delay: TimeInterval
    func exists(_ url: URL) -> Bool { FMFileSystem().exists(url) }
    func size(_ url: URL) -> Int {
        if url.path == path { Thread.sleep(forTimeInterval: delay); return 1 }
        return FMFileSystem().size(url)
    }
    func glob(_ pattern: URL) -> [URL] { FMFileSystem().glob(pattern) }
    func children(of url: URL) -> [URL] { FMFileSystem().children(of: url) }
}
