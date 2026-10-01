import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The editor's save key under every target writes one file, in the folder its
/// target names — and under the clipboard target in the folder macOS names.** The
/// UI test counts files; these read *where* each went, with macOS's folder set to
/// a real directory that is not the Desktop, so "the Desktop" and "macOS's folder"
/// are different answers.
final class TheSaveKeyWritesWhereMacOSWouldTests: XCTestCase {

    private func rig(_ target: SaveTarget, name: String) throws -> (Rig, URL) {
        var settings = ScreenshotsSettings.defaults
        settings.saveTarget = target
        let rig = Rig(home: scratchDirectory(name), settings: settings)
        let macOS = rig.home.appendingPathComponent("Pictures/Shots", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        rig.preferences.savedLocation = macOS.path
        return (rig, macOS)
    }

    func testTheSaveKeyUnderTheClipboardTargetWritesIntoMacOSsFolderAndCopiesNothing() async throws {
        let (rig, macOS) = try rig(.clipboard, name: "shots-save-clipboard")
        let delivery = await rig.session.deliver(makeImage(width: 8, height: 8), saves: true, copies: false,
                                                 fileEvenFromClipboard: true)
        XCTAssertEqual(delivery.refusals.count, 0, "\(delivery.refusals)")
        XCTAssertEqual(rig.writer.written.map { $0.url.deletingLastPathComponent().path }, [macOS.path],
                       "the save key under the clipboard target did not write into the folder macOS names")
        XCTAssertTrue(rig.pasteboard.copies.isEmpty, "the save key took the clipboard as well")
    }

    /// The flag only lends the clipboard target a folder: under the Desktop target the
    /// file still goes to the Desktop, not to macOS's folder.
    func testTheFlagDoesNotMoveAnotherTargetsFile() async throws {
        let (rig, _) = try rig(.desktop, name: "shots-save-desktop")
        _ = await rig.session.deliver(makeImage(width: 8, height: 8), saves: true, copies: false,
                                      fileEvenFromClipboard: true)
        XCTAssertEqual(rig.writer.written.map { $0.url.deletingLastPathComponent().path }, [rig.desktop.path],
                       "the save key moved the Desktop target's file")
    }

    /// The copy key under the clipboard target: the flag is off, no file, one copy.
    func testTheCopyKeyUnderTheClipboardTargetWritesNothing() async throws {
        let (rig, _) = try rig(.clipboard, name: "shots-copy-clipboard")
        _ = await rig.session.deliver(makeImage(width: 8, height: 8), saves: false, copies: true)
        XCTAssertEqual(rig.pasteboard.copies.count, 1, "the copy key did not copy, so the absence below says nothing")
        XCTAssertTrue(rig.writer.written.isEmpty, "the copy key under the clipboard target wrote a file")
    }
}
