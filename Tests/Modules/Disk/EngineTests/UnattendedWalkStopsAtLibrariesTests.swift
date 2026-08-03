import XCTest
@testable import Module_Disk_Engine

/// A scan nobody is watching stops at an application's database; a scan
/// somebody asked for measures it.
///
/// The asymmetry is the point. On 2026-08-03 a background scan walked into
/// `~/Pictures/Photos Library.photoslibrary` and macOS raised a consent dialog
/// that waited at an empty desk. But this module's whole answer is where the
/// space went, and a photo library is often the largest thing on the volume —
/// so the refusal belongs to the unattended walk alone, and both halves need a
/// test or the next person will "simplify" one of them away.
final class UnattendedWalkStopsAtLibrariesTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        let fm = FileManager.default
        fixture = fm.temporaryDirectory
            .appendingPathComponent("helm-library-walk-\(UUID().uuidString)")
        try fm.createDirectory(at: fixture.appendingPathComponent("Photos.photoslibrary/originals"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: fixture.appendingPathComponent("Work"),
                               withIntermediateDirectories: true)
        try Data(count: 200_000).write(
            to: fixture.appendingPathComponent("Photos.photoslibrary/originals/IMG_0001.heic"))
        try Data(count: 50_000).write(to: fixture.appendingPathComponent("Work/notes.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
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
