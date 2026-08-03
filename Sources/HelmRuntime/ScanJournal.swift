import Foundation

/// One scan, in the numbers a journal row is drawn from.
///
/// No localized text: the sentence is written when it is drawn, so a person who
/// switches Helm to another language does not keep a history half in the old one.
public struct ScanEntry: Codable, Equatable, Sendable {
    public let at: Date
    /// What acting on everything found would return. Zero is a real answer — the
    /// scan ran and there was nothing.
    public let bytes: Int
    public let count: Int
    /// How long it took, so a page can say whether a re-scan is a moment or a
    /// walk away.
    public let seconds: TimeInterval
    /// A person pressed the button, rather than the timer coming round.
    public let startedByHand: Bool

    public init(at: Date, bytes: Int, count: Int, seconds: TimeInterval,
                startedByHand: Bool) {
        self.at = at
        self.bytes = bytes
        self.count = count
        self.seconds = seconds
        self.startedByHand = startedByHand
    }
}

/// What a module's scans left behind: the numbers for the last thirty, and the
/// full list for the newest two.
///
/// **Two lists, never more.** The disk cost is then fixed at two files per
/// module rather than growing with use — Disk's own cache is 8 MB of file names,
/// and a journal of ten of those would be 80 MB of Application Support. Two is
/// what "what changed since last time" needs and no more.
public final class ScanJournal: @unchecked Sendable {

    public enum Slot: String, Sendable {
        case current, previous
    }

    /// Thirty scans. A module scanning twice a day keeps a fortnight, which is
    /// long enough to see a pattern and short enough that the file stays small.
    public static let limit = 30

    private let root: URL
    /// One queue, so two scans finishing together land in the order they
    /// finished rather than in scheduler order.
    private let writes = DispatchQueue(label: "helm.scan-journal.write")

    public init(directory: URL) { self.root = directory }

    public convenience init() { self.init(directory: ScanJournal.defaultDirectory) }

    /// A temporary directory under `swift test`, Application Support in the app.
    ///
    /// The test is whether XCTest is loaded, **not** an environment variable:
    /// `XCTestConfigurationFilePath` is set by Xcode and not by `swift test`,
    /// which is how an earlier isolation guard read clean while the suite went
    /// on writing into the real store.
    public static let defaultDirectory: URL = {
        if NSClassFromString("XCTestCase") != nil {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent(
                    "helm-scan-journal-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Helm/Scans", isDirectory: true)
    }()

    // MARK: - Where things live

    public func directory(module: String) -> URL {
        root.appendingPathComponent(module, isDirectory: true)
    }

    public func entriesURL(module: String) -> URL {
        directory(module: module).appendingPathComponent("journal.json")
    }

    public func listURL(module: String, _ slot: Slot) -> URL {
        directory(module: module).appendingPathComponent("\(slot.rawValue).json")
    }

    // MARK: - Reading

    /// Newest first, which is the order a page reads them in.
    public func entries(module: String) -> [ScanEntry] {
        guard let data = try? Data(contentsOf: entriesURL(module: module)),
              let stored = try? JSONDecoder().decode([ScanEntry].self, from: data)
        else { return [] }
        return stored.sorted { $0.at > $1.at }
    }

    public func list(module: String, _ slot: Slot) -> [ScanItem]? {
        guard let data = try? Data(contentsOf: listURL(module: module, slot)) else { return nil }
        return try? JSONDecoder().decode([ScanItem].self, from: data)
    }

    /// What changed between the two lists on disk.
    public func change(module: String) -> ScanChange {
        ScanComparison.between(previous: list(module: module, .previous),
                               current: list(module: module, .current) ?? [])
    }

    // MARK: - Writing

    /// Appends the entry, rotates the lists, and trims to the limit.
    ///
    /// The rotation happens before the write: `current` becomes `previous`, and
    /// what `previous` held is gone. Doing it the other way round leaves the two
    /// files equal after the first scan, and the comparison then reads as
    /// "nothing changed" forever.
    public func record(_ entry: ScanEntry, items: [ScanItem], module: String) {
        writes.sync {
            let directory = self.directory(module: module)
            makePrivateDirectory(directory)

            let current = listURL(module: module, .current)
            let previous = listURL(module: module, .previous)
            if FileManager.default.fileExists(atPath: current.path) {
                try? FileManager.default.removeItem(at: previous)
                try? FileManager.default.moveItem(at: current, to: previous)
            }
            write(items, to: current)

            var kept = entries(module: module)
            kept.append(entry)
            kept.sort { $0.at > $1.at }
            write(Array(kept.prefix(Self.limit)), to: entriesURL(module: module))
        }
    }

    private func makePrivateDirectory(_ url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        // `attributes:` only applies to directories this call creates, and an
        // earlier build may have left one looser.
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    /// Every write sets the mode.
    ///
    /// These files name every path a scan found. `.atomic` writes a temporary
    /// file and renames it, so the mode comes from the process umask — measured,
    /// a fresh atomic write under the ordinary umask lands at **0644** — and a
    /// write over an existing file *keeps that file's* mode. Either way the
    /// privacy would be an accident of the environment rather than a property of
    /// this code.
    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url.path)
    }
}
