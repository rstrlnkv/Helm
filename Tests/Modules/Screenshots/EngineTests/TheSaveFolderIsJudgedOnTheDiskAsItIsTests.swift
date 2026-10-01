import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **`location` names a place, and the place is judged as it stands at the
/// press.** The inputs `TheSaveFolderIsMacOSsOrTheDesktopTests` does not feed: a
/// volume that is not mounted, and the three kinds of symbolic link a person's
/// `location` can be — to a folder (a Dropbox or an external disk linked into
/// the home), to a file, and to nothing. Real paths on a real disk: whether a
/// link is followed is the file system's answer.
final class TheSaveFolderIsJudgedOnTheDiskAsItIsTests: XCTestCase {

    private func fixture() -> (home: URL, desktop: URL) {
        let home = scratchDirectory("shots-disk")
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        return (home, desktop)
    }

    /// An external disk the preference was set on, unplugged since.
    func testAVolumeThatIsNotMountedIsMissingAndTheDesktopTakesThePicture() {
        let (home, desktop) = fixture()
        let volume = "/Volumes/helm-not-mounted-\(UUID().uuidString)/Screenshots"
        XCTAssertFalse(FileManager.default.fileExists(atPath: volume), "the unmounted volume is there")
        XCTAssertEqual(SaveLocation.resolve(raw: volume, desktop: desktop, home: home),
                       SaveFolder(url: desktop, refused: .missing))
    }

    /// A link to a folder is that folder: the picture lands in the target, and
    /// the link is not refused as "not a folder".
    func testALinkToAFolderIsTheFolder() async throws {
        let (home, desktop) = fixture()
        let target = scratchDirectory("shots-disk-target")
        let link = home.appendingPathComponent("Shots")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)

        let folder = SaveLocation.resolve(raw: link.path, desktop: desktop, home: home)
        XCTAssertNil(folder.refused, "a link to a folder was refused: \(String(describing: folder.refused))")
        XCTAssertEqual(folder.url.path, link.path)

        let written = FileShotWriter().write(Data("through the link".utf8), into: folder.url, base: "shot")
        guard case .written(let url) = written else { return XCTFail("\(written)") }
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent(url.lastPathComponent)),
                       Data("through the link".utf8), "the picture did not land in the link's folder")
    }

    func testALinkToAFileIsNotAFolder() throws {
        let (home, desktop) = fixture()
        let file = home.appendingPathComponent("a-file.txt")
        try Data("x".utf8).write(to: file)
        let link = home.appendingPathComponent("Shots")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: file.path)
        XCTAssertEqual(SaveLocation.resolve(raw: link.path, desktop: desktop, home: home),
                       SaveFolder(url: desktop, refused: .notAFolder))
    }

    /// A link whose folder went — the disk it pointed into is the one unplugged.
    func testALinkToNothingIsMissing() throws {
        let (home, desktop) = fixture()
        let link = home.appendingPathComponent("Shots")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                   withDestinationPath: "/Volumes/helm-not-mounted-\(UUID().uuidString)")
        XCTAssertEqual(SaveLocation.resolve(raw: link.path, desktop: desktop, home: home),
                       SaveFolder(url: desktop, refused: .missing))
    }

    /// The whole route: a capture whose `location` names an unplugged disk is
    /// written on the Desktop, and the refusal is logged once.
    func testACaptureAimedAtAnUnpluggedDiskLandsOnTheDesktop() async throws {
        ScreenshotsLog.begin()
        defer { ScreenshotsLog.end() }
        ScreenshotsLog.proveTheLogIsOn()
        let rig = Rig(home: scratchDirectory("shots-disk-rig"))
        rig.preferences.savedLocation = "/Volumes/helm-not-mounted-\(UUID().uuidString)"
        let delivery = await rig.session.deliver(makeImage(width: 4, height: 4), saves: true, copies: false)
        XCTAssertEqual(delivery.files.map { $0.deletingLastPathComponent().path }, [rig.desktop.path])
        XCTAssertEqual(ScreenshotsLog.lines.filter { $0.contains("(missing)") }.count, 1, "\(ScreenshotsLog.lines)")
    }
}
