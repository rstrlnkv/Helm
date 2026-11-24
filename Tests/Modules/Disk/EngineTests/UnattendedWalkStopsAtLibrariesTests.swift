import XCTest
import HelmTestSupport
@testable import Module_Disk_Engine

/// A scan nobody is watching stops at an application's database; a scan
/// somebody asked for measures it.
///
/// Walking into a photo library raises a macOS consent dialog, which nobody is
/// there to answer during a background scan. But a photo library is often the
/// largest thing on the volume, so the refusal belongs to the unattended walk
/// alone, and both halves are held.
final class UnattendedWalkStopsAtLibrariesTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        let fm = FileManager.default
        fixture = scratchDirectory("library-walk")
        try fm.createDirectory(at: fixture.appendingPathComponent("Photos.photoslibrary/originals"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: fixture.appendingPathComponent("Work"),
                               withIntermediateDirectories: true)
        try Data(count: 200_000).write(
            to: fixture.appendingPathComponent("Photos.photoslibrary/originals/IMG_0001.heic"))
        try Data(count: 50_000).write(to: fixture.appendingPathComponent("Work/notes.txt"))
    }

    private func library(in tree: DiskNode) -> DiskNode? {
        tree.children.first { $0.name == "Photos.photoslibrary" }
    }

    func testTheUnattendedWalkDoesNotEnterAPhotoLibrary() throws {
        let tree = try XCTUnwrap(
            DiskScanner(foldThreshold: 0, unattended: true).scan(root: fixture.path))
        // The directory itself may be listed — reading its parent already named
        // it — but nothing inside it was read.
        XCTAssertTrue(library(in: tree)?.children.isEmpty ?? true)
        XCTAssertEqual(library(in: tree)?.bytes ?? 0, 0)
        XCTAssertNotNil(tree.children.first { $0.name == "Work" })
    }

    func testTheScanAPersonAskedForMeasuresIt() throws {
        let tree = try XCTUnwrap(
            DiskScanner(foldThreshold: 0, unattended: false).scan(root: fixture.path))
        let inside = try XCTUnwrap(library(in: tree))
        XCTAssertGreaterThanOrEqual(inside.bytes, 200_000)
    }
}
