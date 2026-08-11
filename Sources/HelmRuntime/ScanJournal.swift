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

    /// A per-process temporary directory under `swift test`, Application Support
    /// in the app. `TestProcess` decides which, and says why it is the question
    /// it is; `TestScratch` is the shape of the temporary one, and Disk's
    /// last-scan cache takes the same one.
    private static let testScratch = TestScratch(prefix: "helm-scan-journal-")

    public static let defaultDirectory: URL = {
        if TestProcess.isRunning { return testScratch.directory() }
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Helm/Scans", isDirectory: true)
    }()

    /// The journal's own name for `TestScratch`'s judgement, narrowed to the
    /// journal's prefix. `AbandonedJournalsTests` asks it here, which is where
    /// the 452 directories were counted, and ARCHITECTURE.md § A harness leaves
    /// nothing behind names it too.
    static func abandonedTestJournals(_ names: [String],
                                      isAlive: (Int32) -> Bool) -> [String] {
        testScratch.abandoned(names, isAlive: isAlive)
    }

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
    ///
    /// **A current list that cannot be read is not an empty one.** It is
    /// missing, or corrupt, or a rotation was interrupted between the move and
    /// the write — and `?? []` turned every one of those into "the last scan
    /// found nothing", which the comparison then reports as the *entire*
    /// previous list having been freed. The same nil-is-not-empty distinction
    /// `ScanReport` is built around, one layer down.
    ///
    /// Answered as "nothing is known" rather than as a change: no previous, no
    /// items, so a page draws no delta instead of a false one.
    public func change(module: String) -> ScanChange {
        guard let current = list(module: module, .current) else {
            return ScanComparison.between(previous: nil, current: [])
        }
        return ScanComparison.between(previous: list(module: module, .previous),
                                      current: current)
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

            // **The entry just recorded always survives the trim.** Sorting
            // everything by date and cutting the tail loses it in two ordinary
            // situations: a clock that was fast yesterday leaves thirty
            // future-stamped rows, so today's corrected one is the oldest of
            // thirty-one and is dropped — while the *list* half of this same
            // call already rotated and wrote. And `Array.sort` is documented as
            // unstable, so thirty rows tied on `at` can drop whichever one they
            // like, including the new one.
            //
            // So it goes first and the rest follow in date order. That is also
            // the honest reading: it is the newest thing that *happened*,
            // whatever the clock says about it.
            let older = entries(module: module)
                .filter { $0 != entry }
                .sorted { $0.at > $1.at }
            write(Array(([entry] + older).prefix(Self.limit)),
                  to: entriesURL(module: module))
        }
    }

    private func makePrivateDirectory(_ url: URL) { PrivateFile.directory(at: url) }

    /// These files name every path a scan found; `PrivateFile` is why the mode
    /// is set on every write rather than once at creation.
    private func write<T: Encodable>(_ value: T, to url: URL) {
        PrivateFile.write(value, to: url)
    }
}
