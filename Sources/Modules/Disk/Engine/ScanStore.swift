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
        } catch {
            // A cache that cannot be written is a missed optimisation, never a
            // reason to fail the scan the user asked for.
        }
    }

    public func load() -> Cached? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Cached.self, from: data)
    }

    public func clear() { try? FileManager.default.removeItem(at: fileURL) }
}
