import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// What the door does with an app it was not shown: spelled another way, changed since the card,
/// unreadable, quoting a glob, up again, refused by macOS.
///
/// A refusal asserts nothing reached the Trash port and nothing was quit, with the app up and the quit
/// agreed, so a missing check shows as a move; a spelling of the same app asserts the bundle moved and
/// was reported moved. `ALaunchpadRemovalMovesOnlyWhatTheIdOwnsAndListsEveryRefusalTests` holds the plain
/// cases.
final class TheDoorMeetsTheInputsNobodyFedTests: XCTestCase {

    private var home: URL!
    private let toolID = "com.acme.tool"

    override func setUpWithError() throws {
        home = scratchDirectory("door-untried")
    }

    private func engine(trash: TrashPort = FakeTrash(), running: RunningAppsPort = FakeRunning(running: []),
                        home override: URL? = nil) -> UninstallerEngine {
        UninstallerEngine(home: override ?? home, apps: FakeApps(), fs: FMFileSystem(), trash: trash,
                          running: running)
    }

    private func candidate(_ path: String, id: String? = nil) -> AppRemovalCandidate {
        AppRemovalCandidate(bundleID: id ?? toolID, path: path, name: "Tool")
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    /// Every door, the app up and the quit agreed: nothing may move, nothing may be quit.
    private func assertRefused(_ c: AppRemovalCandidate, _ why: AppRemovalVerdict.Refusal,
                               file: StaticString = #filePath, line: UInt = #line) async {
        let trash = FakeTrash()
        let running = FakeRunning(running: [c.bundleID, toolID])
        let engine = engine(trash: trash, running: running)
        let verdicts = await engine.removalVerdicts(for: [c])
        let ask = await engine.removalPreview(c)
        let report = await engine.removeApp(c, quittingIfRunning: true)
        XCTAssertEqual(verdicts, [.refused(why)], file: file, line: line)
        XCTAssertEqual(ask, .refused(why), file: file, line: line)
        XCTAssertEqual(report.outcome, .refused, file: file, line: line)
        XCTAssertEqual(trash.trashed, [], "a refused app reached the Trash port", file: file, line: line)
        XCTAssertEqual(running.quits.count, 0, "a refused app was quit", file: file, line: line)
    }

    // MARK: - The plist is the app's own word, and the door reads it where it acts

    func testAnInfoPlistTheDoorCannotReadIsNotOffered() async throws {
        let missing = home.appendingPathComponent("Applications/NoPlist.app/Contents")
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        await assertRefused(candidate(home.path + "/Applications/NoPlist.app"), .notOffered)

        try Data("not a property list".utf8).write(to: missing.appendingPathComponent("Info.plist"))
        await assertRefused(candidate(home.path + "/Applications/NoPlist.app"), .notOffered)

        try (["CFBundleIdentifier": 5] as NSDictionary).write(to: missing.appendingPathComponent("Info.plist"))
        await assertRefused(candidate(home.path + "/Applications/NoPlist.app"), .notOffered)
    }

    func testAnIdThatDiffersByWhitespaceOrCaseIsAnotherAppsId() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: toolID)
        for spelled in [" \(toolID)", "\(toolID) ", "COM.ACME.TOOL", "\(toolID)\n"] {
            await assertRefused(candidate(path, id: spelled), .notOffered)
        }
        XCTAssertTrue(exists(path))
    }

    // MARK: - The same app spelled another way, and a folder that is not one of the four

    func testTheFolderInAnotherCaseIsTheSameFolderAndTheBundleIsReportedMoved() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: toolID)
        let spelled = home.path + "/applications/Tool.app"
        let trash = FakeTrash()

        let report = await engine(trash: trash).removeApp(candidate(spelled), quittingIfRunning: false)

        XCTAssertEqual(report.outcome, .moved,
                       "the app went, and the report says it did not (the removed list holds another spelling)")
        XCTAssertFalse(exists(path))
    }

    func testAnotherNormalisationOfTheNameIsTheSameBundleAndReportedMoved() async throws {
        let nfc = "Caf\u{e9}.app", nfd = "Cafe\u{301}.app"
        let path = try writeAppBundle(home.appendingPathComponent("Applications/\(nfc)"), id: toolID)
        let report = await engine().removeApp(candidate(home.path + "/Applications/" + nfd),
                                              quittingIfRunning: false)
        XCTAssertEqual(report.outcome, .moved)
        XCTAssertFalse(exists(path))
    }

    func testAFolderOfTheVendorUnderSetappIsNotOfferedAndSetappItselfIs() async throws {
        let direct = try writeAppBundle(home.appendingPathComponent("Applications/Setapp/Tool.app"), id: toolID)
        let verdicts = await engine().removalVerdicts(for: [candidate(direct)])
        XCTAssertEqual(verdicts, [.removable], "control: Setapp's own folder is one of the four")

        let nested = try writeAppBundle(home.appendingPathComponent("Applications/Setapp/Sub/Tool.app"),
                                        id: toolID)
        await assertRefused(candidate(nested), .notOffered)
    }

    func testAPlainFileNamedLikeAnAppIsNotOffered() async throws {
        let folder = home.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("File.app")
        try Data("x".utf8).write(to: file)
        await assertRefused(candidate(file.path), .notOffered)
        XCTAssertTrue(exists(file.path))
    }

    func testAnApplicationsFolderThatIsALinkToAnotherDiskStillMovesAndIsReportedMoved() async throws {
        let elsewhere = home.appendingPathComponent("Disk/Apps")
        let real = try writeAppBundle(elsewhere.appendingPathComponent("Tool.app"), id: toolID)
        try FileManager.default.createSymbolicLink(atPath: home.appendingPathComponent("Applications").path,
                                                   withDestinationPath: elsewhere.path)
        let report = await engine().removeApp(candidate(home.path + "/Applications/Tool.app"),
                                              quittingIfRunning: false)
        XCTAssertEqual(report.outcome, .moved)
        XCTAssertFalse(exists(real))
    }

    // MARK: - Between the card and the press

    func testAnAppRenamedAfterTheCardIsGoneAndNothingOfItsMoves() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: toolID)
        let cache = try write("Library/Caches/\(toolID)/d", in: home).deletingLastPathComponent().path
        let c = candidate(path)
        let ask = await engine().removalPreview(c)
        guard case .ready = ask else { return XCTFail("precondition: the card was given: \(ask)") }
        try FileManager.default.moveItem(atPath: path, toPath: home.path + "/Applications/Renamed.app")

        await assertRefused(c, .gone)
        XCTAssertTrue(exists(cache), "its leftovers went with an app that was not there")
        XCTAssertTrue(exists(home.path + "/Applications/Renamed.app"))
    }

    func testAnAppReplacedByALinkAfterTheCardLeavesTheTargetAlone() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: toolID)
        let target = try writeAppBundle(home.appendingPathComponent("Documents/Precious.app"), id: toolID)
        let c = candidate(path)
        try FileManager.default.removeItem(atPath: path)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)

        await assertRefused(c, .notOffered)
        XCTAssertTrue(exists(target), "the app behind the link went")
    }

    func testAnAppReplacedByAnotherAppAfterTheCardIsNotTheOneShown() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: toolID)
        let c = candidate(path)
        try FileManager.default.removeItem(atPath: path)
        try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: "com.other.thing")

        await assertRefused(c, .notOffered)
        XCTAssertTrue(exists(path))
    }

    /// An app that starts itself again when it is quit — a login item, a helper: the quit is asked,
    /// the question is asked again, and nothing moves.
    func testAnAppThatRelaunchesItselfOnQuitIsHeldAndNothingMoves() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: toolID)
        let cache = try write("Library/Caches/\(toolID)/d", in: home).deletingLastPathComponent().path
        let trash = FakeTrash()
        let running = FakeRunning(running: [toolID], relaunching: [toolID: toolID])

        let report = await engine(trash: trash, running: running)
            .removeApp(candidate(path), quittingIfRunning: true)

        XCTAssertEqual(running.quits.map(\.0), [toolID], "precondition: the quit was asked")
        XCTAssertEqual(report.outcome, .stillRunning)
        XCTAssertEqual(trash.trashed, [])
        XCTAssertTrue(exists(path) && exists(cache))
    }

    // MARK: - An id that is a pattern, and a leftover that is a link

    /// The id is the app's own word. A glob or a separator in it builds no candidate, so the bundle
    /// moves alone and what a pattern would have reached stays.
    func testAnIdThatIsAPatternOrAPathTakesOnlyTheBundle() async throws {
        for id in ["*", "com.acme.*", "com.acme.t?ol", "../Documents", "com/acme"] {
            let root = scratchDirectory("door-pattern")
            let path = try writeAppBundle(root.appendingPathComponent("Applications/Tool.app"), id: id)
            let strangers = try write("Library/Caches/com.other.app/d", in: root).deletingLastPathComponent().path
            let keep = try write("Documents/keep", in: root).path
            let trash = FakeTrash()

            let report = await engine(trash: trash, home: root).removeApp(candidate(path, id: id),
                                                                         quittingIfRunning: false)

            XCTAssertEqual(trash.trashed, [path], "id «\(id)»")
            XCTAssertEqual(report.outcome, .moved, "id «\(id)»")
            XCTAssertTrue(exists(strangers) && exists(keep), "id «\(id)»: something not its own went")
        }
    }

    func testALeftoverThatIsALinkIntoDocumentsMovesTheLinkAndNotWhatItLeadsTo() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: toolID)
        let keep = try write("Documents/keep", in: home).path
        let caches = home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: caches.appendingPathComponent(toolID).path,
                                                   withDestinationPath: home.appendingPathComponent("Documents").path)

        let report = await engine().removeApp(candidate(path), quittingIfRunning: false)

        XCTAssertTrue(exists(keep), "what the link led to was taken")
        XCTAssertNotEqual(report.outcome, .refused)
    }

    // MARK: - The report is a count of what happened to every path

    func testEveryPathIsInTheRemovedOrTheFailedListAndTheBytesAreOnlyWhatMoved() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: toolID)
        _ = try write("Applications/Tool.app/Contents/MacOS/Tool", in: home, bytes: 4_096)
        let cache = try write("Library/Caches/\(toolID)/d", in: home, bytes: 50_000)
            .deletingLastPathComponent().path
        let bundleBytes = FMFileSystem().size(URL(fileURLWithPath: path))
        let cacheBytes = FMFileSystem().size(URL(fileURLWithPath: cache))
        XCTAssertGreaterThan(cacheBytes, bundleBytes, "precondition: the two sizes tell the paths apart")

        // The leftover refused: the bundle's bytes only.
        let cacheRefused = FakeTrash(failing: [cache])
        let first = engine(trash: cacheRefused)
        _ = await first.removalPreview(candidate(path))
        let one = await first.removeApp(candidate(path), quittingIfRunning: false)
        XCTAssertEqual(one.outcome, .movedWithFailures)
        XCTAssertEqual(one.failed.count, 1)
        XCTAssertEqual(one.freedBytes, bundleBytes, "a refused path was counted as freed")

        // Fresh bundle; both refused: nothing freed, two reasons, and the app is not «moved».
        try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: toolID)
        let bothRefused = FakeTrash(failing: [path, cache])
        let second = engine(trash: bothRefused)
        _ = await second.removalPreview(candidate(path))
        let none = await second.removeApp(candidate(path), quittingIfRunning: false)
        XCTAssertEqual(none.outcome, .refused)
        XCTAssertEqual(none.failed.count, 1, "a refusal is in neither list; the leftovers wait for the app")
        XCTAssertEqual(none.freedBytes, 0)

        // The bundle refused, the leftover not: the app is still installed and the report says so.
        let bundleRefused = FakeTrash(failing: [path])
        let other = await engine(trash: bundleRefused).removeApp(candidate(path), quittingIfRunning: false)
        XCTAssertEqual(other.outcome, .refused, "an app that is still installed was reported as moved")
        XCTAssertEqual(other.failed.count, 1)
    }
}
