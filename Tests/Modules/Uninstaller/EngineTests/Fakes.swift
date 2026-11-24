import Foundation
import XCTest
@testable import Module_Uninstaller_Engine

// The uninstaller engine's doubles, in one place because they are the target's.
//
// They are not variants of one fake. The four `TrashPort` doubles are four
// subjects: one that never removes anything, one that records and can refuse a
// named path, one that really moves files, and one that refuses everything so
// the reason can be argued about. Collapsed, a state the real port can be in
// could not be written down.

/// The one `FileSystemPort` fake: a Mac with none of the files a test asks about
/// (`FakeFS()`: nothing exists, nothing weighs anything, no glob and no listing finds
/// a thing), or the files the test names, each reading counted.
///
/// - `existing`: path → size, what exists.
/// - `listings`: directory listings for the orphan scan, keyed by parent path.
/// - `everyPathExistsAt`: every path exists at that many bytes, and nothing is listed.
/// - `globbing`: a glob resolves against the siblings in `existing` and a folder lists
///   its children from it, the way the system port does; a fake that answers `[]` for
///   a glob cannot see a defect in which names one reaches.
/// - `onDisk`: what is not scripted here is the real disk's answer.
/// - `slowSizes`: a path whose walk takes that long, as on a Mac that is busy.
/// - `reads`: every question put to it, so "no read" is a number.
final class FakeFS: FileSystemPort, @unchecked Sendable {
    var existing: [String: Int]
    var listings: [String: [String]]
    var everyPathExistsAt: Int?
    var globbing: Bool
    var onDisk: Bool
    var slowSizes: [String: TimeInterval]
    private let lock = NSLock()
    private var asked = 0
    var reads: Int { lock.withLock { asked } }

    init(existing: [String: Int] = [:], listings: [String: [String]] = [:],
         everyPathExistsAt: Int? = nil, globbing: Bool = false, onDisk: Bool = false,
         slowSizes: [String: TimeInterval] = [:]) {
        self.existing = existing
        self.listings = listings
        self.everyPathExistsAt = everyPathExistsAt
        self.globbing = globbing
        self.onDisk = onDisk
        self.slowSizes = slowSizes
    }

    private func count() { lock.withLock { asked += 1 } }

    func exists(_ url: URL) -> Bool {
        count()
        if everyPathExistsAt != nil { return true }
        if onDisk { return FMFileSystem().exists(url) }
        return existing[url.path] != nil
    }
    func size(_ url: URL) -> Int {
        count()
        if let delay = slowSizes[url.path] { Thread.sleep(forTimeInterval: delay); return 1 }
        if let size = everyPathExistsAt { return size }
        if onDisk { return FMFileSystem().size(url) }
        return existing[url.path] ?? 0
    }
    func glob(_ pattern: URL) -> [URL] {
        count()
        if onDisk { return FMFileSystem().glob(pattern) }
        guard globbing else { return [] }
        let dir = pattern.deletingLastPathComponent().path
        let name = pattern.lastPathComponent
        return existing.keys
            .filter { ($0 as NSString).deletingLastPathComponent == dir }
            .filter { GlobMatch.matches(($0 as NSString).lastPathComponent, pattern: name) }
            .sorted()
            .map { URL(fileURLWithPath: $0) }
    }
    func children(of url: URL) -> [URL] {
        count()
        if let names = listings[url.path] { return names.map { url.appendingPathComponent($0) } }
        if onDisk { return FMFileSystem().children(of: url) }
        guard globbing else { return [] }
        return existing.keys
            .filter { ($0 as NSString).deletingLastPathComponent == url.path }
            .sorted()
            .map { URL(fileURLWithPath: $0) }
    }
}
struct FakeApps: AppLister {
    func installedBundleIDs() -> Set<String> { Set(apps.map(\.bundleID)) }
    var known: Set<String> = []
    func isKnownToSystem(bundleID: String) -> Bool { known.contains(bundleID) }
    var apps: [InstalledApp] = []
    func installedApps() -> [InstalledApp] { apps }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
    /// Every state Spotlight has: a date (in the table), no record (not in it),
    /// and slow — `lookupDelay` per call, for a Mac that is reindexing.
    var opened: [String: Date] = [:]
    var lookupDelay: TimeInterval = 0
    func lastOpened(path: String) -> Date? {
        if lookupDelay > 0 { Thread.sleep(forTimeInterval: lookupDelay) }
        return opened[path]
    }
    /// Optional, the way the port is: `nil` is a Trash this process was not allowed
    /// to read (`TheOfferSwitchSaysWhatItIsDoingTests`). A non-optional would not
    /// satisfy the requirement and would silently hand every test the default `[]`.
    var trashed: [TrashedApp]? = []
    func trashedApps() -> [TrashedApp]? { trashed }
    /// A real Mac's two answers, which differ. `ids` is what `contentsOfDirectory`
    /// finds; `nested` is installed and running and lives one folder down, so only
    /// LaunchServices knows about it.
    static func installed(_ ids: Set<String>, nested: Set<String> = []) -> FakeApps {
        FakeApps(known: ids.union(nested), apps: ids.map {
            InstalledApp(name: $0, bundleID: $0, path: "/Applications/\($0).app")
        })
    }
}
final class FakeTrash: TrashPort, @unchecked Sendable {
    var trashed: [String] = []
    let failing: Set<String>
    init(failing: [String] = []) { self.failing = Set(failing) }
    func trashItem(_ url: URL) -> TrashOutcome {
        if failing.contains(url.path) {
            // 513 = NSFileWriteNoPermissionError, what macOS returns for a
            // protected container.
            return TrashOutcome(succeeded: false, errorCode: 513, message: "denied")
        }
        trashed.append(url.path)
        // Gone from its place, as a real move leaves it: `HelmTrash.remove` asks.
        try? FileManager.default.removeItem(at: url)
        return .success
    }
}
/// macOS refusing every path, with 513 (NSFileWriteNoPermissionError, what it
/// answers for a bundle it will not move) and no sentence worth reading.
struct RefusesEverything: TrashPort {
    func trashItem(_ url: URL) -> TrashOutcome {
        TrashOutcome(succeeded: false, errorCode: 513, message: "denied")
    }
}
/// A running app that can actually stop running, and start again: the person
/// can relaunch an app while reading the review, and `waitUntilGone` and the
/// second asking exist for both directions.
final class FakeRunning: RunningAppsPort, @unchecked Sendable {
    private let lock = NSLock()
    private var running: Set<String>
    /// Apps that ignore a quit request, so the deadline path has a subject.
    private let stubborn: Set<String>
    /// Quitting the key brings the value back up.
    ///
    /// A relaunch landing inside a batch's quit loop, as a login item or helper
    /// restarting its app does. Deterministic where a `sleep` racing the deadline
    /// is not; `launch` alone cannot reach inside the batch.
    private let relaunching: [String: String]
    /// Records (bundleID, force) so tests can assert how an app was quit.
    private(set) var quits: [(String, Bool)] = []

    /// How long an app takes to actually go after being asked.
    ///
    /// Not zero: the app would be gone before `waitUntilGone` was called, and a
    /// test of the wait would pass with the wait deleted.
    private let quitAfter: TimeInterval

    init(running: [String], stubborn: [String] = [], quitAfter: TimeInterval = 0,
         relaunching: [String: String] = [:]) {
        self.running = Set(running)
        self.stubborn = Set(stubborn)
        self.quitAfter = quitAfter
        self.relaunching = relaunching
    }

    func isRunning(bundleID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running.contains(bundleID)
    }

    /// The app is up again, started by the person or a login item while somebody
    /// reads a review screen, without asking Helm.
    func launch(_ bundleID: String) {
        lock.lock(); running.insert(bundleID); lock.unlock()
    }

    func quit(bundleID: String, force: Bool) {
        lock.lock()
        quits.append((bundleID, force))
        let willGo = !stubborn.contains(bundleID)
        let delay = quitAfter
        if willGo, delay == 0 { running.remove(bundleID) }
        // Whatever this quit starts, it starts whether or not the app being
        // asked goes anywhere itself.
        if let other = relaunching[bundleID] { running.insert(other) }
        lock.unlock()
        guard willGo, delay > 0 else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            lock.lock(); running.remove(bundleID); lock.unlock()
        }
    }
}

// MARK: - Tests

/// Nothing here removes anything. The engine takes a `TrashPort` whether or
/// not the test is about removal; a test that wants a refusal or a record wants
/// `FakeTrash(failing:)`, `MovingTrash` or `RefusesEverything`.
///
/// Enforced by `XCTFail`: a test that starts reaching `trashItem` says so,
/// instead of taking a `.success` it was never entitled to.
struct NoTrash: TrashPort {
    func trashItem(_ url: URL) -> TrashOutcome {
        XCTFail("no test here trashes — this test wants a trash double of its own")
        return .success
    }
}

/// **Nothing here is running**, and nothing is asked to quit.
///
/// Not `FakeRunning(running: [])`, a machine whose apps can start and stop,
/// asked when none is up. This is a test that never asks for a quit.
///
/// `isRunning` answers `false`, a real answer. `quit` fails, as `NoTrash` does:
/// a quit nobody expected must not pass silently. A test that wants an app to
/// go down wants `FakeRunning` with a `quitAfter`.
struct NoRunning: RunningAppsPort {
    func isRunning(bundleID: String) -> Bool { false }
    func quit(bundleID: String, force: Bool) {
        XCTFail("no test here quits anything — this test wants FakeRunning")
    }
}

/// A bundle at `app` whose `Info.plist` carries `id`: the engine reads the id from
/// there, and it is what ties a refusal to the app owning a system extension.
@discardableResult
func writeAppBundle(_ app: URL, id: String) throws -> String {
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    try (["CFBundleIdentifier": id] as NSDictionary)
        .write(to: contents.appendingPathComponent("Info.plist"))
    return app.path
}
