import Foundation
import HelmRuntime
import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

/// A `TrashPort` that really moves what it is given.
///
/// `FakeTrash` leaves the file in place, so "the child went with its parent"
/// cannot happen with it. This one moves the item into a bin of its own and
/// answers `NSFileNoSuchFileError` for a path that is not there, as
/// `FileManager.trashItem` does. The bin is inside the test's temporary tree.
final class MovingTrash: TrashPort, @unchecked Sendable {
    private let bin: URL
    private let lock = NSLock()
    private var movedPaths: [String] = []

    var moved: [String] { lock.lock(); defer { lock.unlock() }; return movedPaths }

    init(bin: URL) {
        self.bin = bin
        try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    }

    func trashItem(_ url: URL) -> TrashOutcome {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return TrashOutcome(succeeded: false, errorCode: NSFileNoSuchFileError,
                                message: "The file doesn’t exist.")
        }
        let destination = bin.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.moveItem(at: url, to: destination)
        } catch let error as NSError {
            return TrashOutcome(succeeded: false, errorCode: error.code,
                                message: error.localizedDescription)
        }
        lock.lock(); movedPaths.append(url.path); lock.unlock()
        return .success
    }
}

/// What one press of Move to Trash does to a tree, over real files.
///
/// The batch goes through `HelmTrash`, shared with three other modules, and
/// these guard the rules that only show up on a tree: a folder basketed with a
/// file inside it, two names for one file, and a row already gone.
final class TrashBatchFollowsTheSharedRulesTests: XCTestCase {

    private var home: URL!
    private var trash: MovingTrash!

    override func setUpWithError() throws {
        // The engine is told this is home: `RemovableScope` refuses everything
        // outside one, and the test keeps the gate.
        home = scratchDirectory("unbatch")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Caches"),
                                               withIntermediateDirectories: true)
        trash = MovingTrash(bin: home.appendingPathComponent("bin"))
    }

    /// The real filesystem port, so the sizes are the ones production reads.
    private func engine() -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(),
                          trash: trash, running: FakeRunning(running: []))
    }

    @discardableResult
    private func write(_ url: URL, bytes: Int) throws -> String {
        try write(url.lastPathComponent, in: url.deletingLastPathComponent(),
                  bytes: bytes).path
    }

    /// What production would say this path frees (`FMFileSystem.size` is this
    /// call), so no assertion depends on APFS block sizes.
    private func weight(_ path: String) -> Int {
        FileWeight.allocated(of: URL(fileURLWithPath: path))
    }

    private func caches(_ relative: String) -> URL {
        home.appendingPathComponent("Library/Caches").appendingPathComponent(relative)
    }

    /// An app bundle where people really keep them — `~/Applications` — with one
    /// file inside, since a bundle that reports its directory entry reports zero.
    private func appBundle(bytes: Int) throws -> String {
        let app = home.appendingPathComponent("Applications")
            .appendingPathComponent("Tool-\(UUID().uuidString).app")
        try write(app.appendingPathComponent("Contents/MacOS/Tool"), bytes: bytes)
        return app.path
    }

    // MARK: - A folder and something inside it

    /// A file whose folder already moved went to the Trash with it: it counts as
    /// removed, not refused. Asserted for both orders and absolutely, since two
    /// wrongs of equal size satisfy a comparison.
    func testAChildTakenWithItsParentIsRemovedWhicheverOrderTheBatchArrivesIn() async throws {
        for parentFirst in [true, false] {
            let folder = caches("Ghost-\(UUID().uuidString)")
            let child = try write(folder.appendingPathComponent("inside.bin"), bytes: 200_000)
            let batch = parentFirst ? [folder.path, child] : [child, folder.path]
            let order = parentFirst ? "parent first" : "child first"

            let result = await engine().trashPaths(batch)

            XCTAssertEqual(Set(result.trashed), [folder.path, child],
                           "\(order): \(result.trashed.count) of 2 reported as moved")
            XCTAssertEqual(result.failures.map(\.path), [],
                           "\(order): a path this batch took is not something the person "
                           + "can act on")
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "\(order)")
            XCTAssertGreaterThanOrEqual(result.freedBytes, 200_000, "\(order)")
            XCTAssertLessThan(result.freedBytes, 400_000,
                              "\(order): the 200 KB inside the folder was counted twice — "
                              + "once for the folder and once for the file basketed with it")
        }
    }

    // MARK: - Two names for one file

    /// A hard link is one allocation with two names, and the second name frees
    /// nothing. Both are real leftovers, and both are offered.
    func testTwoNamesForOneFileFreeItsBytesOnce() async throws {
        let first = try write(caches("Ghost-\(UUID().uuidString)/big.bin"), bytes: 300_000)
        let second = caches("Helper-\(UUID().uuidString)/same.bin")
        try FileManager.default.createDirectory(at: second.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: URL(fileURLWithPath: first), to: second)

        let result = await engine().trashPaths([first, second.path])

        XCTAssertEqual(Set(result.trashed), [first, second.path])
        XCTAssertGreaterThanOrEqual(result.freedBytes, 300_000)
        XCTAssertLessThan(result.freedBytes, 600_000,
                          "one file's bytes were counted once per name it wears")
    }

    // MARK: - A row that was already gone

    /// A path that vanished before the batch started is a refusal with a reason,
    /// not dropped from both lists: the person is looking at a stale list.
    func testAPathAlreadyGoneIsRefusedRatherThanDroppedFromBothLists() async throws {
        let present = try write(caches("Ghost-\(UUID().uuidString)/here.bin"), bytes: 8_000)
        let vanished = caches("Ghost-\(UUID().uuidString)/gone.bin").path

        let result = await engine().trashPaths([present, vanished])

        XCTAssertEqual(result.trashed, [present])
        XCTAssertEqual(result.failed, [vanished],
                       "a stale row reached neither list, so the count lied about it")
        XCTAssertEqual(result.failures.first?.reason,
                       TrashFailure.Reason.missing,
                       "a stale row was told macOS refused it, which sends somebody to the "
                       + "Finder to look at a file that is not there")
    }

    // MARK: - What the refusal carries

    /// The engine has the last word on deletion: a path outside the folders an
    /// app may leave things in is refused here, with the reason, however it got
    /// into the basket.
    func testAPathOutsideTheScopeIsRefusedWithItsOwnReason() async throws {
        let inside = try write(caches("Ghost-\(UUID().uuidString)/here.bin"), bytes: 8_000)
        let outside = home.appendingPathComponent("Documents/thesis.txt")
        try write(outside, bytes: 4_000)

        let result = await engine().trashPaths([inside, outside.path])

        XCTAssertEqual(result.trashed, [inside])
        XCTAssertEqual(result.failures.map(\.reason),
                       [TrashFailure.Reason.outOfScope])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path),
                      "the refusal was reported and the file taken anyway")
    }

    // MARK: - What it says was freed

    /// Three different sizes: with equal ones, counting one path twice and
    /// another not at all would come to the same total.
    func testTheAppAndItsLeftoversAreCountedOnceEach() async throws {
        let cache = try write(caches("Ghost-\(UUID().uuidString)/big.bin"), bytes: 200_000)
        let plist = try write(caches("Ghost-\(UUID().uuidString)/small.plist"), bytes: 8_000)
        let app = try appBundle(bytes: 100_000)
        let weights = [cache, plist, app].map(weight)

        let result = await engine().trashPaths([cache, plist, app])

        XCTAssertEqual(Set(trash.moved), [cache, plist, app])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(Set(weights).count, 3, "the three paths must not weigh the same")
        XCTAssertEqual(result.freedBytes, weights.reduce(0, +))
        XCTAssertGreaterThanOrEqual(result.freedBytes, 308_000, "nothing was weighed at all")
    }

    /// Only what moved counts: a refused path's bytes are still on the disk.
    func testARefusedPathIsNotCountedAsFreed() async throws {
        let cache = try write(caches("Ghost-\(UUID().uuidString)/big.bin"), bytes: 200_000)
        let locked = try write(caches("Ghost-\(UUID().uuidString)/locked.bin"), bytes: 8_000)
        let app = try appBundle(bytes: 100_000)
        let moved = [cache, app].map(weight)
        let engine = UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(),
                                       trash: FakeTrash(failing: [locked]),
                                       running: FakeRunning(running: []))

        let result = await engine.trashPaths([cache, locked, app])

        XCTAssertEqual(result.failed, [locked])
        XCTAssertEqual(result.freedBytes, moved.reduce(0, +))
        XCTAssertGreaterThanOrEqual(result.freedBytes, 300_000, "nothing was weighed at all")
    }

    /// macOS's own sentence reaches the failure sheet, under the classified
    /// reason. It does not cross `HelmTrash.Result`; the module carries it.
    func testWhatMacOSSaidReachesTheReport() async throws {
        let locked = try write(caches("Ghost-\(UUID().uuidString)/locked.bin"), bytes: 8_000)
        let engine = UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(),
                                       trash: FakeTrash(failing: [locked]),
                                       running: FakeRunning(running: []))

        let result = await engine.trashPaths([locked])

        XCTAssertEqual(result.failures.map(\.message), ["denied"])
        XCTAssertEqual(result.failures.map(\.reason),
                       [TrashFailure.Reason.noPermission])
    }
}
