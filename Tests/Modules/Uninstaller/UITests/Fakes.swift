import Foundation
import XCTest
import HelmRuntime
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

// The same two placeholders the engine's tests share, and they are here rather
// than shared with that target because a test target cannot depend on another
// one. The duplication that is left is this file against
// `EngineTests/Fakes.swift`; the duplication that was here was five copies
// under two names across three files.

/// **Nothing here removes anything.** These tests are about what the view model
/// shows, and the engine behind it takes a `TrashPort` whether or not anybody
/// is going to remove something.
///
/// **And that claim has a runner now.** The engine's copy at least carried a
/// measurement saying an unconditional refusal changed nothing there; this one
/// carried the claim with nothing behind it at all — and this is the target
/// where it could hide, because a view model handed a `.success` it never
/// earned shows a removal that did not happen. A test that wants a refusal, or
/// wants to know what was asked for, wants `FakeTrash` in the engine's tests or
/// a double of its own here. The return is unreachable by the time it is read.
struct NoTrash: TrashPort {
    func trashItem(_ url: URL) -> TrashOutcome {
        XCTFail("no test here trashes — this test wants a trash double of its own")
        return .success
    }
}

/// **Nothing here is running**, and nothing is asked to quit.
///
/// `isRunning` answers `false` because that is a real answer to a question
/// these tests really ask. `quit` is not an answer: a view model test that
/// cares whether an app is up, and how long it takes to go, wants `FakeRunning`
/// with a `quitAfter` — zero would make the wait vacuous.
struct NoRunning: RunningAppsPort {
    func isRunning(bundleID: String) -> Bool { false }
    func quit(bundleID: String, force: Bool) {
        XCTFail("no test here quits anything — this test wants FakeRunning")
    }
}

/// The engine's place for the model's tests: it answers what it is told to, and
/// writes down every call — **port states and a log, nothing else**. The model
/// refuses a stopped state itself, so a test of that reads `calls`; a test of a
/// state the engine can really be in (a batch macOS refused, an app still up)
/// builds the `UninstallResult` the engine would.
///
/// Held answers are the exception, each behind a method a test calls:
/// `land()` for the sizes and `holdScans()` for the scans, because a fake that
/// answers at once cannot show what the model does while an answer is out.
final class AnsweringWork: UninstallerWork, @unchecked Sendable {

    enum Call: Equatable {
        case listApps, appSizes, lastOpened, scanOrphans, trashedAppLeftovers, backgroundScan
        case setSortOrder(AppSortOrder)
        case scan(bundleID: String)
        case trashPaths([String], quitting: Bool)
        case setWatchingTrash(Bool)
        case dismissTrashedApp(String)
    }

    private let lock = NSLock()
    private var log: [Call] = []
    private let apps: [InstalledApp]
    private let scans: [String: ScanResult]
    private let removal: UninstallResult
    private let offers: [TrashedAppLeftovers]
    private let sizes: [String: Int]?
    private var opens: [String: Date] = [:]
    private var unreadDates: [String] = []
    private var order: AppSortOrder = .standard
    private var sizesLanded = true
    private var scansHeld = false
    private var scansDone = 0

    /// - Parameter sizes: what `appSizes` answers; the listed apps' own sizes
    ///   when nil.
    init(apps: [InstalledApp] = [],
         scans: [String: ScanResult] = [:],
         removal: UninstallResult = UninstallResult(trashed: [], freedBytes: 0),
         offers: [TrashedAppLeftovers] = [],
         sizes: [String: Int]? = nil) {
        self.apps = apps
        self.scans = scans
        self.removal = removal
        self.offers = offers
        self.sizes = sizes
    }

    /// What Spotlight says: a date per path, a path missing from it having no
    /// record, and `unread` the paths its read never reached.
    func setOpened(_ dates: [String: Date], unread: [String] = []) {
        lock.withLock { opens = dates; unreadDates = unread }
    }

    /// `appSizes` answers only after `land()`.
    func holdSizes() { lock.withLock { sizesLanded = false } }
    func land() { lock.withLock { sizesLanded = true } }
    /// Each `scan` answers only after `releaseScans()`.
    func holdScans() { lock.withLock { scansHeld = true } }
    func releaseScans() { lock.withLock { scansHeld = false } }
    /// How many scans have been asked for.
    var scansAsked: Int { lock.withLock { scansDone } }

    var calls: [Call] { lock.withLock { log } }

    /// The batches handed to `trashPaths`, in order.
    var batches: [(paths: [String], quitting: Bool)] {
        calls.compactMap { if case .trashPaths(let paths, let quitting) = $0 { (paths, quitting) } else { nil } }
    }

    /// The scans asked for, by bundle id.
    var scanned: [String] {
        calls.compactMap { if case .scan(let id) = $0 { id } else { nil } }
    }

    /// The bundle ids written to the permanent "declined" record, in order.
    var dismissed: [String] {
        calls.compactMap { if case .dismissTrashedApp(let id) = $0 { id } else { nil } }
    }

    private func note(_ call: Call) { lock.withLock { log.append(call) } }

    func listApps() async -> [InstalledApp] { note(.listApps); return apps }

    func appSizes(_ list: [InstalledApp]) async -> [String: Int] {
        note(.appSizes)
        while !lock.withLock({ sizesLanded }) { try? await Task.sleep(nanoseconds: 5_000_000) }
        return sizes ?? Dictionary(uniqueKeysWithValues: apps.map { ($0.path, $0.sizeBytes) })
    }

    func lastOpened(_ list: [InstalledApp], deadline: TimeInterval, ceiling: Int,
                    now: Date) async -> AppOpenedReading {
        note(.lastOpened)
        return lock.withLock { AppOpenedReading(opened: opens, unread: unreadDates) }
    }

    var sortOrder: AppSortOrder { lock.withLock { order } }

    /// The engine keeps what it is told, as the real one does — a fake that forgot
    /// it would answer the next `sortOrder` with the old order.
    func setSortOrder(_ next: AppSortOrder) {
        note(.setSortOrder(next))
        lock.withLock { order = next }
    }

    func scan(bundleID: String, appPath: String, appName: String) async -> ScanResult {
        note(.scan(bundleID: bundleID))
        let found = scans[bundleID] ?? ScanResult(bundleID: bundleID, appPath: appPath,
                                                  appSizeBytes: 0, leftovers: [], runningNow: false)
        lock.withLock { scansDone += 1 }
        while lock.withLock({ scansHeld }) { try? await Task.sleep(nanoseconds: 5_000_000) }
        return found
    }

    func scanOrphans() async -> [OrphanGroup] { note(.scanOrphans); return [] }

    func trashPaths(_ paths: [String], quittingRunningApps: Bool) async -> UninstallResult {
        note(.trashPaths(paths, quitting: quittingRunningApps))
        return removal
    }

    var trashWatch: TrashWatch { .off }
    func setWatchingTrash(_ on: Bool) { note(.setWatchingTrash(on)) }

    func trashedAppLeftovers() async -> [TrashedAppLeftovers] { note(.trashedAppLeftovers); return offers }

    func dismissTrashedApp(bundleID: String) { note(.dismissTrashedApp(bundleID)) }

    func backgroundScan() async -> ScanReport? { note(.backgroundScan); return nil }
}

/// The model over a work, with the Trash arrivals nobody feeds.
@MainActor func modelOver(_ work: any UninstallerWork) -> UninstallerViewModel {
    UninstallerViewModel(work: work, trashArrivals: AsyncStream { _ in })
}

/// Answers the sweep at once and holds the batch open until released.
///
/// **It does not answer until it is told to.** A fake that answers synchronously
/// releases the gate before the call it is gating returns, so a test built on
/// one passes whether or not the gate exists.
final class HeldWork: UninstallerWork, @unchecked Sendable {
    private let lock = NSLock()
    private var trashCount = 0
    var trashRequests: Int { lock.withLock { trashCount } }
    private let released = AsyncStream<Void>.makeStream()
    private let offers: [TrashedAppLeftovers]

    init(offers: [TrashedAppLeftovers]) { self.offers = offers }

    func release() { released.continuation.finish() }

    func trashedAppLeftovers() async -> [TrashedAppLeftovers] { offers }

    func trashPaths(_ paths: [String], quittingRunningApps: Bool) async -> UninstallResult {
        lock.withLock { trashCount += 1 }
        // Hangs until `release()`. A `return` here would clear `busy` before the
        // caller resumed, and the gate would be untested.
        for await _ in released.stream {}
        return UninstallResult(trashed: [], freedBytes: 0)
    }

    func listApps() async -> [InstalledApp] { [] }
    func appSizes(_ list: [InstalledApp]) async -> [String: Int] { [:] }
    func lastOpened(_ list: [InstalledApp], deadline: TimeInterval, ceiling: Int,
                    now: Date) async -> AppOpenedReading { AppOpenedReading(opened: [:]) }
    var sortOrder: AppSortOrder { .standard }
    func setSortOrder(_ order: AppSortOrder) {}
    func scan(bundleID: String, appPath: String, appName: String) async -> ScanResult {
        ScanResult(bundleID: bundleID, appPath: appPath, appSizeBytes: 0, leftovers: [], runningNow: false)
    }
    func scanOrphans() async -> [OrphanGroup] { [] }
    var trashWatch: TrashWatch { .off }
    func setWatchingTrash(_ on: Bool) {}
    func dismissTrashedApp(bundleID: String) {}
    func backgroundScan() async -> ScanReport? { nil }
}
