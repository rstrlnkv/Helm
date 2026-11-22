import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// The catalog records Finder's date added of each bundle: not for the system's own folder, not for a symlink, and the read of it
/// is one `getattrlist` per app (`resourceValues` kept 350 bytes an app), held by the allocator's books as `WalkFootprintTests` does.
final class TheDateAddedIsReadOncePerAppAndCostsTheWalkNothingTests: XCTestCase {
    private func bundle(_ name: String, id: String, in root: URL) throws {
        let contents = root.appendingPathComponent(name).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
    }

    func testAnAppHasTheDateItWasAddedAndASymlinkedOneHasNone() throws {
        let root = scratchDirectory("added-dates")
        try bundle("A.app", id: "a", in: root)
        let target = scratchDirectory("added-target")
        try bundle("Real.app", id: "real", in: target)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Linked.app"), withDestinationURL: target.appendingPathComponent("Real.app"))
        let apps = Dictionary(uniqueKeysWithValues: FileSystemAppCatalog(roots: [root]).read(reason: .refresh).apps.map { ($0.id, $0) })
        let added = try XCTUnwrap(apps["a"]?.added, "the control: a plain bundle has a date")
        XCTAssertLessThan(abs(added.timeIntervalSinceNow), 3600, "added just now")
        XCTAssertNotNil(apps["real"], "the symlinked bundle is read")
        XCTAssertNil(apps["real"]?.added, "and has no date: the link's is not the app's")
    }

    func testTheSystemsOwnFolderHasNoDates() {
        XCTAssertFalse(FileSystemAppCatalog.recordsDate(forRoot: URL(fileURLWithPath: "/System/Applications", isDirectory: true)))
        XCTAssertTrue(FileSystemAppCatalog.recordsDate(forRoot: URL(fileURLWithPath: "/Applications", isDirectory: true)))
        XCTAssertTrue(FileSystemAppCatalog.recordsDate(forRoot: URL(fileURLWithPath: "/System/Applications Elsewhere", isDirectory: true)))
    }

    func testReadingTheDatesCostsTheWalkItsTreeAndNothingMore() throws {
        let root = scratchDirectory("added-footprint")
        let count = 1500
        for index in 0..<count { try bundle("App\(index).app", id: "app.\(index)", in: root) }
        let catalog = FileSystemAppCatalog(roots: [root])
        _ = catalog.read(reason: .refresh)
        let before = AllocatorBooks.allocatedBytes()
        let apps = catalog.read(reason: .refresh).apps
        let after = AllocatorBooks.allocatedBytes()
        // The subject first: every app was read and every one has its date.
        XCTAssertEqual(apps.count, count)
        XCTAssertEqual(apps.filter { $0.added != nil }.count, count)
        let perApp = Double(after - before) / Double(count)
        print(String(format: "read %d apps with dates: allocator grew %.1f KB (%.0f bytes/app)", count, Double(after - before) / 1024, perApp))
        // **The ceiling sits between two measurements of this fixture** (1500 bundles, second read, two runs each):
        //
        //     no date read at all:                1642 bytes/app (the apps the read returns)
        //     getattrlist, as the port does:      1642 bytes/app
        //     `resourceValues`, pool or none:     1992 bytes/app, and `removeAllCachedResourceValues` 1962
        XCTAssertLessThan(perApp, 1_800, "the read grew by more than the apps it returned: the date read is keeping what it looked at")
    }
}
