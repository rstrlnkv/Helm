import Foundation
import XCTest
@testable import Module_Uninstaller_Engine

// The uninstaller engine's doubles, in one place because they are the target's
// and not any one test file's.
//
// **They are not variants of one fake.** Four things can stand in for
// `TrashPort` and each is a different subject: one that never removes anything,
// one that records what it was asked to remove and can be told to refuse a
// named path, one that really moves files, and one that refuses everything so
// the *reason* can be argued about. Collapsing them would make a fake simpler
// than the port it stands for, and a state the real port can be in would stop
// being writable down.

struct FakeFS: FileSystemPort {
    let existing: [String: Int]
    /// Directory listings for the orphan scan, keyed by parent path.
    var listings: [String: [String]] = [:]
    func exists(_ url: URL) -> Bool { existing[url.path] != nil }
    func size(_ url: URL) -> Int { existing[url.path] ?? 0 }
    func glob(_ pattern: URL) -> [URL] { [] }
    func children(of url: URL) -> [URL] {
        (listings[url.path] ?? []).map { url.appendingPathComponent($0) }
    }
}
struct FakeApps: AppLister {
    func installedBundleIDs() -> Set<String> { Set(apps.map(\.bundleID)) }
    var known: Set<String> = []
    func isKnownToSystem(bundleID: String) -> Bool { known.contains(bundleID) }
    var apps: [InstalledApp] = []
    func installedApps() -> [InstalledApp] { apps }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
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
        return .success
    }
}
/// A running app that can actually stop running.
///
/// `running` was a `let`, so quitting changed nothing the port could report and
/// "the app is gone now" was unrepresentable — which is why nothing could test
/// a wait for it, and why the wait was a fixed 800 ms sleep in the view model.
final class FakeRunning: RunningAppsPort, @unchecked Sendable {
    private let lock = NSLock()
    private var running: Set<String>
    /// Apps that ignore a quit request, so the deadline path has a subject.
    private let stubborn: Set<String>
    /// Records (bundleID, force) so tests can assert how an app was quit.
    private(set) var quits: [(String, Bool)] = []

    /// How long an app takes to actually go after being asked.
    ///
    /// Zero would make every test of a *wait* vacuous: the app would be gone
    /// before `waitUntilGone` was even called, so the assertion would hold with
    /// the wait deleted. A real app takes a moment, and that moment is the
    /// whole subject.
    private let quitAfter: TimeInterval

    init(running: [String], stubborn: [String] = [], quitAfter: TimeInterval = 0) {
        self.running = Set(running)
        self.stubborn = Set(stubborn)
        self.quitAfter = quitAfter
    }

    func isRunning(bundleID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running.contains(bundleID)
    }

    func quit(bundleID: String, force: Bool) {
        lock.lock()
        quits.append((bundleID, force))
        let willGo = !stubborn.contains(bundleID)
        let delay = quitAfter
        if willGo, delay == 0 { running.remove(bundleID) }
        lock.unlock()
        guard willGo, delay > 0 else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            lock.lock(); running.remove(bundleID); lock.unlock()
        }
    }
}

// MARK: - Tests

/// **Nothing here removes anything.** The engine takes a `TrashPort` whether or
/// not the test is about removal, and most of these are about which apps are
/// offered — the removal has its own tests, behind `RemovableScope`.
///
/// A test that wants a refusal, or wants to know what was asked for, wants
/// `FakeTrash(failing:)`, `MovingTrash` or `BlamingTrash` instead.
///
/// **The claim is enforced rather than measured once.** It used to say that
/// making this refuse everything with 513 changed no result in this target —
/// which was true, was measured by hand on one afternoon, and had nothing to
/// keep it true. `XCTFail` is that same measurement with a runner behind it: a
/// test that starts reaching `trashItem` says so on the run that starts it,
/// instead of quietly taking a `.success` it was never entitled to. The return
/// is unreachable by the time it is read.
struct NoTrash: TrashPort {
    func trashItem(_ url: URL) -> TrashOutcome {
        XCTFail("no test here trashes — this test wants a trash double of its own")
        return .success
    }
}

/// **Nothing here is running**, and nothing is asked to quit.
///
/// Not `FakeRunning(running: [])`, which is the same answer for a different
/// reason: that one is a machine whose apps can start, stop and refuse to stop,
/// asked at a moment when none of them is up. This is a test that never asks.
///
/// The two halves are deliberately different shapes. `isRunning` answers
/// `false` because that is a real answer to a real question — nothing here is
/// up, and tests do ask. `quit` is not an answer at all: it used to record
/// nothing under the same hand-measurement as `NoTrash`, and now it fails,
/// because a quit nobody counts and a quit nobody expected are the same
/// silence. A test that wants an app which is up and can go down after being
/// asked wants `FakeRunning` — with a `quitAfter`, or a wait for it is over
/// before it is reached.
struct NoRunning: RunningAppsPort {
    func isRunning(bundleID: String) -> Bool { false }
    func quit(bundleID: String, force: Bool) {
        XCTFail("no test here quits anything — this test wants FakeRunning")
    }
}
