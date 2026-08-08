import Foundation
import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// A `TrashPort` that really moves what it is given.
///
/// `FakeTrash` records a path and leaves the file where it is, so a folder and
/// something inside it both "succeed" and the case the batch rules exist for —
/// the child went with its parent — cannot happen. No test of it could fail,
/// whatever anybody wrote. This one moves the item into a bin of its own and
/// answers `NSFileNoSuchFileError` for a path that is not there, which is what
/// `FileManager.trashItem` does.
///
/// The bin sits inside the test's own temporary tree, so nothing here reaches
/// the Trash of whoever ran `swift test`.
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
/// The engine wrote its own batch loop beside the one in `HelmTrash`, which
/// three other modules share, and the copy was missing the parts that only
/// show up on a tree: a folder basketed with a file inside it, two names for
/// one file, and a row that was already gone. Each of these is a rule
/// `HelmTrash` states in a comment and the copy never learned.
final class TrashBatchFollowsTheSharedRulesTests: XCTestCase {

    private var home: URL!
    private var bin: URL!
    private var trash: MovingTrash!

    override func setUpWithError() throws {
        // The engine is told this is home: `RemovableScope` refuses everything
        // outside one, and a test exempted from that gate is a test of a
        // different program.
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-unbatch-\(UUID().uuidString)")
        bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Caches"),
                                               withIntermediateDirectories: true)
        trash = MovingTrash(bin: bin)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// The real filesystem port, so the sizes are the ones production reads.
    /// A fake sizing table would make every byte assertion here a statement
    /// about the table.
    private func engine() -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(),
                          trash: trash, running: FakeRunning(running: []))
    }

    @discardableResult
    private func write(_ url: URL, bytes: Int) throws -> String {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url.path
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

    /// Basket a folder on one screen and a file inside it on another and the
    /// child's turn comes after the folder has already moved. It is in the
    /// Trash; saying nothing about it makes the count say one when two went,
    /// and reporting a refusal sends the person looking for a file that is
    /// there.
    ///
    /// Asserted for both orders and absolutely, not by comparing the two
    /// results: two wrongs of equal size satisfy a comparison.
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

    /// A hard link is one allocation wearing two names, and taking the second
    /// name frees nothing. Both are real leftovers — a helper's cache linked
    /// into the app's own — and both are offered.
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

    /// The list on screen is minutes old. A path that vanished before the
    /// batch started is a refusal with a reason — the person is looking at a
    /// stale list and that is the one thing worth telling them about it. It
    /// used to be dropped from both lists, so the report said nothing at all.
    func testAPathAlreadyGoneIsRefusedRatherThanDroppedFromBothLists() async throws {
        let present = try write(caches("Ghost-\(UUID().uuidString)/here.bin"), bytes: 8_000)
        let vanished = caches("Ghost-\(UUID().uuidString)/gone.bin").path

        let result = await engine().trashPaths([present, vanished])

        XCTAssertEqual(result.trashed, [present])
        XCTAssertEqual(result.failed, [vanished],
                       "a stale row reached neither list, so the count lied about it")
        XCTAssertEqual(result.failures.first?.reason,
                       TrashFailure.Reason.systemRefused)
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

    /// Three sizes, deliberately all different: with equal ones a batch that
    /// counted one path twice and another not at all would come to the same
    /// total, and the assertion below would bless it.
    func testTheAppAndItsLeftoversAreCountedOnceEach() async throws {
        let cache = try write(caches("Ghost-\(UUID().uuidString)/big.bin"), bytes: 200_000)
        let plist = try write(caches("Ghost-\(UUID().uuidString)/small.plist"), bytes: 8_000)
        let app = try appBundle(bytes: 100_000)
        let weights = [cache, plist, app].map { FileWeight.allocated(of: URL(fileURLWithPath: $0)) }

        let result = try await engine().uninstall(appPath: app, paths: [cache, plist])

        XCTAssertEqual(Set(trash.moved), [cache, plist, app])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(Set(weights).count, 3, "the three paths must not weigh the same")
        XCTAssertEqual(result.freedBytes, weights.reduce(0, +))
        XCTAssertGreaterThanOrEqual(result.freedBytes, 308_000, "nothing was weighed at all")
    }

    /// Only what moved counts. The bytes of a path macOS refused are still on
    /// the disk, and a banner that included them would be telling the person
    /// they got back space they still owe.
    func testARefusedPathIsNotCountedAsFreed() async throws {
        let cache = try write(caches("Ghost-\(UUID().uuidString)/big.bin"), bytes: 200_000)
        let locked = try write(caches("Ghost-\(UUID().uuidString)/locked.bin"), bytes: 8_000)
        let app = try appBundle(bytes: 100_000)
        let moved = [cache, app].map { FileWeight.allocated(of: URL(fileURLWithPath: $0)) }
        let engine = UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(),
                                       trash: FakeTrash(failing: [locked]),
                                       running: FakeRunning(running: []))

        let result = try await engine.uninstall(appPath: app, paths: [cache, locked])

        XCTAssertEqual(result.failed, [locked])
        XCTAssertEqual(result.freedBytes, moved.reduce(0, +))
        XCTAssertGreaterThanOrEqual(result.freedBytes, 300_000, "nothing was weighed at all")
    }

    /// macOS's own sentence reaches the failure sheet, which draws it under the
    /// classified reason as the evidence behind it. The classification crosses
    /// `HelmTrash.Result`; this does not, and it is the module's own to carry.
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
