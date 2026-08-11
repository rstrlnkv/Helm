import Foundation
import HelmRuntime

/// The last scan, kept on disk so reopening the module shows the ring instead
/// of a minute-long progress bar. One slot: the ring shows one tree.
public final class ScanStore: @unchecked Sendable {
    public struct Cached: Codable, Sendable {
        public let result: ScanResult
        public let savedAt: Date
    }

    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    public convenience init() { self.init(directory: ScanStore.defaultDirectory) }

    /// A per-process temporary directory under `swift test`, Application Support
    /// in the app — the answer `ScanJournal.defaultDirectory` next door already
    /// gives, for the same reason and through the same `TestScratch`.
    ///
    /// **This file is an index of every file name on somebody's volume**, and
    /// without the question every test that renders Disk's page read theirs:
    /// `DiskViewModel` takes its store as a defaulted argument, so a page built
    /// through `shared(vm:)` restores whatever that file holds, on a detached task
    /// that races the render's settle loop. `restoreLastScan` also calls `clear()`
    /// when the saved root has gone, so a suite run could *delete* their cache
    /// and not only read it. `TheSuiteDoesNotReadTheUsersLastScanTests` carries
    /// what it cost the ratchets, in layers and in seconds.
    ///
    /// Resolved once. Every `ScanStore()` would otherwise ask, and asking sweeps
    /// `$TMPDIR` — a walk that belongs to the process, not to each store built in
    /// it.
    private static let defaultDirectory: URL = {
        if TestProcess.isRunning { return TestScratch(prefix: "helm-disk-store-").directory() }
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Helm/Disk", isDirectory: true)
    }()

    public var fileURL: URL { directory.appendingPathComponent("last-scan.json") }

    /// 0700 on the folder and 0600 on the file, through `PrivateFile`: this
    /// cache is a full index of file names on the volume. `~/Library` is already
    /// private, but that is the enclosing folder's doing, not this one's.
    ///
    /// A cache that cannot be written is a missed optimisation, never a reason
    /// to fail the scan the user asked for, so the result is dropped rather than
    /// raised.
    public func save(_ result: ScanResult, at date: Date = Date()) {
        PrivateFile.directory(at: directory)
        PrivateFile.write(Cached(result: result, savedAt: date), to: fileURL)
    }

    public func load() -> Cached? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Cached.self, from: data)
    }

    /// The same read, off whatever actor asked for it.
    ///
    /// The file is a full index of the volume — measured here at 7 MB and
    /// 42 000 nodes, which is 95 ms to decode and 81 ms to encode. Both used to
    /// happen on the main actor, so opening Disk Space froze for a tenth of a
    /// second and every scan and every basket emptying froze again.
    public func loadDetached() async -> Cached? {
        let url = fileURL
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Cached.self, from: data)
        }.value
    }

    public func saveDetached(_ result: ScanResult, at date: Date = Date()) {
        let store = self
        Task.detached(priority: .utility) { store.save(result, at: date) }
    }

    public func clear() { try? FileManager.default.removeItem(at: fileURL) }
}
