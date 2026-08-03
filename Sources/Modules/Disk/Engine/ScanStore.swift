import Foundation

/// The last scan, kept on disk so reopening the module shows the ring instead
/// of a minute-long progress bar. One slot: the ring shows one tree.
public final class ScanStore: @unchecked Sendable {
    public struct Cached: Codable, Sendable {
        public let result: ScanResult
        public let savedAt: Date
    }

    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    public convenience init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        self.init(directory: base.appendingPathComponent("Helm/Disk", isDirectory: true))
    }

    public var fileURL: URL { directory.appendingPathComponent("last-scan.json") }

    public func save(_ result: ScanResult, at date: Date = Date()) {
        do {
            // 0700: the cache is a full index of file names on the volume.
            // ~/Library is already private, but that is the enclosing folder's
            // doing, not this one's.
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            // `attributes:` only applies to directories this call creates, and
            // anyone who ran an earlier build already has one at 0755.
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: directory.path)
            let data = try JSONEncoder().encode(Cached(result: result, savedAt: date))
            try data.write(to: fileURL, options: .atomic)
            // Every write, not once at creation. `.atomic` writes a temporary
            // file and renames it, so the mode comes from the process umask on a
            // fresh write and from the replaced file on a subsequent one —
            // measured at 0644 either way in a plain process. Until this line
            // the privacy of an index of every filename on the volume was an
            // accident of whichever umask the app happened to run under. The
            // scan journal beside it answers to the same rule.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: fileURL.path)
        } catch {
            // A cache that cannot be written is a missed optimisation, never a
            // reason to fail the scan the user asked for.
        }
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
