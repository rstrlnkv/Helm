import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A folder chosen in Helm is a string in a file anything running as the
/// person can write, and it is judged exactly as macOS's `location` is.**
/// Missing, a file, a folder nobody may write, a relative path, nothing stored
/// at all: each lands on the Desktop with its reason, and the session says so
/// in a line of its own. A test of the Desktop and Documents is here too, since
/// they go through the same door by path.
final class TheChosenFolderIsJudgedLikeMacOSsTests: XCTestCase {
    override func setUp() { super.setUp(); ScreenshotsLog.begin() }
    override func tearDown() { ScreenshotsLog.end(); super.tearDown() }

    private func fixture() throws -> (home: URL, desktop: URL, locations: ScreenshotsLocations) {
        let home = scratchDirectory("shots-chosen")
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        for folder in [desktop, documents] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return (home, desktop, ScreenshotsLocations(home: home, desktop: desktop, documents: documents))
    }

    /// Every way a chosen folder can be unusable, the same set `resolve` is held to for `location`.
    private func badFolders(in home: URL) throws -> [(String, String?, SaveFolderRefusal)] {
        let file = try write("a-file.txt", in: home)
        let locked = home.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        return [("nothing stored", nil, .empty),
                ("an empty string", "", .empty),
                ("a relative path", "Pictures", .relative),
                ("a folder that is not there", home.appendingPathComponent("gone").path, .missing),
                ("a file instead of a folder", file.path, .notAFolder),
                ("a folder nobody may write", locked.path, .notWritable)]
    }

    func testAChosenFolderThatIsNotUsableIsTheDesktopWithItsReason() throws {
        let (home, desktop, locations) = try fixture()
        for (what, stored, reason) in try badFolders(in: home) {
            let settings = ScreenshotsSettings(saveTarget: .other, otherFolder: stored)
            let folder = SaveLocation.folder(for: settings, macOS: nil, locations: locations)
            XCTAssertEqual(folder, SaveFolder(url: desktop, refused: reason), what)
        }
    }

    func testAGoodChosenFolderIsUsedAndTheClipboardHasNone() throws {
        let (home, _, locations) = try fixture()
        let chosen = home.appendingPathComponent("Chosen", isDirectory: true)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        XCTAssertEqual(SaveLocation.folder(for: ScreenshotsSettings(saveTarget: .other, otherFolder: chosen.path),
                                           macOS: nil, locations: locations),
                       SaveFolder(url: chosen, refused: nil))
        XCTAssertNil(SaveLocation.folder(for: ScreenshotsSettings(saveTarget: .clipboard, otherFolder: chosen.path),
                                         macOS: nil, locations: locations))
    }

    func testDocumentsAndTheDesktopAreJudgedToo() throws {
        let (home, desktop, _) = try fixture()
        let gone = ScreenshotsLocations(home: home, desktop: desktop,
                                        documents: home.appendingPathComponent("no-such-documents"))
        XCTAssertEqual(SaveLocation.folder(for: ScreenshotsSettings(saveTarget: .documents), macOS: nil, locations: gone),
                       SaveFolder(url: desktop, refused: .missing), "a Documents folder that is not there was used")
        let noDesktop = ScreenshotsLocations(home: home, desktop: home.appendingPathComponent("no-desktop"))
        XCTAssertEqual(SaveLocation.folder(for: ScreenshotsSettings(saveTarget: .desktop), macOS: nil,
                                           locations: noDesktop)?.refused, .missing)
    }

    func testMacOSsOwnRawValueIsStillWhatTheMacOSTargetReads() throws {
        let (home, desktop, locations) = try fixture()
        let pictures = home.appendingPathComponent("Pictures", isDirectory: true)
        try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        XCTAssertEqual(SaveLocation.folder(for: ScreenshotsSettings(saveTarget: .macOS), macOS: pictures.path,
                                           locations: locations)?.url.path, pictures.path)
        XCTAssertEqual(SaveLocation.folder(for: ScreenshotsSettings(saveTarget: .macOS), macOS: 5, locations: locations),
                       SaveFolder(url: desktop, refused: .notAPath))
        // The raw value macOS holds is read for macOS's target and no other.
        XCTAssertEqual(SaveLocation.folder(for: ScreenshotsSettings(saveTarget: .desktop), macOS: pictures.path,
                                           locations: locations)?.url, desktop)
    }

    /// Through the session: the file lands on the Desktop and the log says it was
    /// **a folder chosen in Helm** that was refused — not macOS's.
    func testASessionSavesToTheDesktopAndSaysWhichFolderWasRefused() async throws {
        ScreenshotsLog.proveTheLogIsOn()
        let home = scratchDirectory("shots-chosen-session")
        for (what, stored, reason) in try badFolders(in: home) {
            ScreenshotsLog.begin()
            let rig = Rig(home: home, settings: ScreenshotsSettings(saveTarget: .other, otherFolder: stored))
            let delivery = await rig.session.deliver(makeImage(width: 8, height: 8), saves: true, copies: false)
            XCTAssertEqual(delivery.files.map { $0.deletingLastPathComponent().path }, [rig.desktop.path], what)
            XCTAssertTrue(ScreenshotsLog.lines.contains { $0.contains("folder chosen in Helm") && $0.contains(reason.rawValue) },
                          "\(what): \(ScreenshotsLog.lines)")
            XCTAssertFalse(ScreenshotsLog.lines.contains { $0.contains("macOS names") },
                           "\(what): a folder chosen in Helm was reported as macOS's")
        }
    }
}
