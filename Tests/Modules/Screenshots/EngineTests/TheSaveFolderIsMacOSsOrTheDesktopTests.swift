import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The folder is macOS's, read and never written, or it is the Desktop.**
/// `com.apple.screencapture`'s `location` is a preference any process running as
/// the person can write, and `defaults write … location -int 5` is a legal
/// file. Every kind of garbage lands on the Desktop with a reason, and the
/// ordinary absent key lands there with none. Real directories, never a fake:
/// whether a folder is a folder is the disk's answer.
final class TheSaveFolderIsMacOSsOrTheDesktopTests: XCTestCase {

    private func fixture() -> (home: URL, desktop: URL) {
        let home = scratchDirectory("shots-folder")
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        return (home, desktop)
    }

    func testAnAbsentLocationIsTheDesktopAndNotARefusal() {
        let (home, desktop) = fixture()
        let folder = SaveLocation.resolve(raw: nil, desktop: desktop, home: home)
        XCTAssertEqual(folder, SaveFolder(url: desktop, refused: nil))
    }

    func testAnExistingFolderIsUsed() throws {
        let (home, desktop) = fixture()
        let pictures = home.appendingPathComponent("Pictures/Shots", isDirectory: true)
        try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        let folder = SaveLocation.resolve(raw: pictures.path, desktop: desktop, home: home)
        XCTAssertEqual(folder.url.path, pictures.path)
        XCTAssertNil(folder.refused)
    }

    func testATildeIsTheHomeOfTheCallerAndNotOfTheProcess() throws {
        let (home, desktop) = fixture()
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Shots"),
                                                withIntermediateDirectories: true)
        let folder = SaveLocation.resolve(raw: "~/Shots", desktop: desktop, home: home)
        XCTAssertEqual(folder.url.path, home.appendingPathComponent("Shots").path,
                       "a tilde was expanded against a home other than the one it was given")
        XCTAssertNil(folder.refused)
    }

    /// The five kinds of garbage a property list can hold, and the path that does
    /// not name a folder, each with the reason it is refused for.
    func testEveryKindOfGarbageIsRefusedByNameAndTakesTheDesktop() throws {
        let (home, desktop) = fixture()
        let file = try write("a-file.txt", in: home)
        let cases: [(String, Any, SaveFolderRefusal)] = [
            ("an integer", 5, .notAPath),
            ("data", Data([1, 2, 3]), .notAPath),
            ("a list", ["/tmp"], .notAPath),
            ("an empty string", "", .empty),
            ("only spaces", "   ", .empty),
            ("a relative path", "Pictures", .relative),
            ("a folder that is not there", home.appendingPathComponent("gone").path, .missing),
            ("a file instead of a folder", file.path, .notAFolder),
        ]
        for (what, raw, reason) in cases {
            let folder = SaveLocation.resolve(raw: raw, desktop: desktop, home: home)
            XCTAssertEqual(folder.refused, reason, what)
            XCTAssertEqual(folder.url, desktop, "\(what) did not fall back to the Desktop")
        }
    }

    /// A 0555 directory exists, is a directory, and cannot be written. The mode
    /// is put back by a teardown block, which runs before the scratch sweep: a
    /// directory left unreadable is otherwise swept before it is made readable
    /// again and the harness leaves it behind.
    func testAFolderNobodyMayWriteIsRefused() throws {
        let (home, desktop) = fixture()
        let locked = home.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        let folder = SaveLocation.resolve(raw: locked.path, desktop: desktop, home: home)
        XCTAssertEqual(folder.refused, .notWritable)
        XCTAssertEqual(folder.url, desktop)
    }

    /// The engine side: a refused folder is logged once where it is acted on, and
    /// the picture still lands on the Desktop.
    func testARefusedFolderIsLoggedAndThePictureStillLands() async throws {
        ScreenshotsLog.begin()
        defer { ScreenshotsLog.end() }
        ScreenshotsLog.proveTheLogIsOn()
        let rig = Rig(home: scratchDirectory("shots-folder-session"))
        rig.preferences.savedLocation = 7
        rig.capture.outcome = .frozen(Freeze(displays: [Rig.display(1)], windows: []))

        let delivery = await rig.session.captureScreens()

        XCTAssertEqual(delivery.files.count, 1)
        XCTAssertEqual(delivery.files.first?.deletingLastPathComponent().path, rig.desktop.path)
        XCTAssertEqual(ScreenshotsLog.lines.filter { $0.contains("notAPath") }.count, 1, "\(ScreenshotsLog.lines)")
    }
}
