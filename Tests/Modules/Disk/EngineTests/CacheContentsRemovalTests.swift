import XCTest
import HelmRuntime
@testable import Module_Disk_Engine

/// A real cache folder on disk, refused by macOS the way `~/Library/Caches` is,
/// with children that go quietly. The move is injected — nothing here reaches
/// anybody's Trash — but everything else is real: real files, real sizes, real
/// `FileWeight`, and the report `HelmTrash` builds out of them.
final class CacheContentsRemovalTests: XCTestCase {
    /// Above `DiskAdvisor`'s 100 MB floor, so the advice under test is the one
    /// the app would really produce. Measured at 29 ms to write.
    private let childBytes = 36_000_000
    private let children = ["Firefox", "Adobe", "Spotify"]

    private var root = URL(fileURLWithPath: "/")
    private var cachesPath = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = scratchDirectory("disk-cache-contents")
        cachesPath = root.appendingPathComponent("Library/Caches").path
        for child in children {
            try write("Library/Caches/\(child)/data.bin", in: root, bytes: childBytes)
        }
    }

    /// The advice the app would show for this tree, through the real advisor.
    private func cacheAdvice() throws -> DiskAdvice {
        let tree = try XCTUnwrap(DiskScanner().scan(root: root.path))
        let advice = DiskAdvisor.advise(root: tree, rootPath: root.path, home: root.path)
        return try XCTUnwrap(advice.first { $0.kind == .cache }, "\(advice.map(\.path))")
    }

    /// Refuses `denied` the way macOS refuses a folder carrying `deny delete`,
    /// and really removes everything else — so what is left on disk afterwards
    /// is what the report claims.
    private func move(refusing denied: Set<String>) -> (URL) throws -> Void {
        { url in
            if denied.contains(url.path) {
                throw NSError(domain: NSCocoaErrorDomain, code: 513)   // NSFileWriteNoPermissionError
            }
            try FileManager.default.removeItem(at: url)
        }
    }

    /// **The hazard is real.** Without this the two tests below would pass with
    /// the container perfectly trashable and prove nothing at all.
    func testTheContainerItselfIsRefused() {
        let result = HelmTrash.remove(allowed: [cachesPath], module: "disk",
                                      trashing: move(refusing: [cachesPath]))
        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.refused, [HelmTrash.Refusal(path: cachesPath,
                                                          reason: .noPermission)])
        XCTAssertEqual(result.freedBytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachesPath))
    }

    /// The same refusal, and the same press: the advice names the contents, so
    /// the folder macOS is protecting is never asked for.
    func testTheContentsGoAndTheFolderStays() throws {
        let advice = try cacheAdvice()
        let paths = DiskRemovalPlan.targets(basket: [cachesPath], advice: [advice])
        let (allowed, refused) = UserFileScope.partition(Array(Set(paths)))
        let result = HelmTrash.remove(allowed: allowed, outOfScope: refused, module: "disk",
                                      trashing: move(refusing: [cachesPath]))

        XCTAssertEqual(result.removed.sorted(), children.map { cachesPath + "/" + $0 }.sorted())
        XCTAssertEqual(result.refused, [])
        // At least what was written, and no more than a block per file over it.
        XCTAssertGreaterThanOrEqual(result.freedBytes, 3 * childBytes)
        XCTAssertLessThan(result.freedBytes, 3 * childBytes + 3 * 65_536)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachesPath),
                      "applications expect their cache folder to exist")
        for child in children {
            XCTAssertFalse(FileManager.default.fileExists(atPath: cachesPath + "/" + child), child)
        }
    }

    /// Partial is the normal outcome here — a running application holds its own
    /// cache open — so the report has to name what stayed, not sum it into the
    /// count. One refusal, by path, with the reason macOS gave.
    func testAChildHeldByARunningAppIsNamedInTheReport() throws {
        let held = cachesPath + "/Spotify"
        let advice = try cacheAdvice()
        let paths = DiskRemovalPlan.targets(basket: [cachesPath], advice: [advice])
        let (allowed, refused) = UserFileScope.partition(Array(Set(paths)))
        let result = HelmTrash.remove(allowed: allowed, outOfScope: refused, module: "disk",
                                      trashing: move(refusing: [cachesPath, held]))

        XCTAssertEqual(result.removed.sorted(),
                       [cachesPath + "/Adobe", cachesPath + "/Firefox"])
        XCTAssertEqual(result.refused, [HelmTrash.Refusal(path: held, reason: .noPermission)])
        XCTAssertGreaterThanOrEqual(result.freedBytes, 2 * childBytes)
        XCTAssertLessThan(result.freedBytes, 2 * childBytes + 2 * 65_536)
        XCTAssertTrue(FileManager.default.fileExists(atPath: held))

        // And the row that stays behind says what is still there, not what was.
        let left = DiskRemovalPlan.remaining([advice], after: result.removed)
        XCTAssertEqual(left.first?.targets.map(\.path), [held])
        XCTAssertLessThan(left.first?.bytes ?? 0, advice.bytes)
        // One child's worth, against the figure this test wrote — not against
        // anything the code under test also computed.
        XCTAssertGreaterThanOrEqual(left.first?.bytes ?? 0, childBytes)
        XCTAssertLessThan(left.first?.bytes ?? 0, childBytes + 65_536)
    }
}
