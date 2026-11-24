import Foundation

/// One scan, in the numbers a journal row is drawn from.
///
/// No localized text: the sentence is written when it is drawn, so a person who
/// switches Helm to another language does not keep a history half in the old one.
public struct ScanEntry: Codable, Equatable, Sendable {
    let at: Date
    /// What acting on everything found would return. Zero is a real answer — the
    /// scan ran and there was nothing.
    let bytes: Int
    let count: Int
    /// How long it took, so a page can say whether a re-scan is a moment or a
    /// walk away.
    let seconds: TimeInterval

    public init(at: Date, bytes: Int, count: Int, seconds: TimeInterval) {
        self.at = at
        self.bytes = bytes
        self.count = count
        self.seconds = seconds
    }

    // No "started by hand" flag: the journal has one writer, the unattended
    // `ScanCoordinator`, so everything read back is about work nobody watched,
    // which `ScanNews` relies on. An interactive writer would make that a
    // decision to take then.
    //
    // Older `journal.json` files carry a `startedByHand` key; `JSONDecoder`
    // ignores a key it has no property for. An *added* key would not decode
    // from old files.
}

/// What a module's scans left behind: the numbers for the last thirty, and the
/// full list for the newest two.
///
/// **Two lists, never more.** The disk cost is fixed at two files per module
/// rather than growing with use (a list can be megabytes of file names), and
/// two is what "what changed since last time" needs.
public final class ScanJournal: @unchecked Sendable {

    enum Slot: String, Sendable {
        case current, previous
    }

    /// Thirty scans. A completed scan holds its module for a day, so entries
    /// stand a day or more apart and thirty keep a month or more, which is long
    /// enough to see a pattern and short enough that the file stays small.
    static let limit = 30

    private let root: URL
    /// One queue, so two scans finishing together land in the order they
    /// finished rather than in scheduler order.
    private let writes = DispatchQueue(label: "helm.scan-journal.write")

    public init(directory: URL) { self.root = directory }

    public convenience init() { self.init(directory: ScanJournal.defaultDirectory) }

    /// A per-process temporary directory under `swift test`, Application Support
    /// in the app. `TestProcess` decides which, and says why it is the question
    /// it is; `TestScratch` is the shape of the temporary one.
    private static let testScratch = TestScratch(prefix: "helm-scan-journal-")

    public static let defaultDirectory: URL = {
        if TestProcess.isRunning { return testScratch.directory() }
        return HelmSupport.directory.appendingPathComponent("Scans", isDirectory: true)
    }()

    /// The journal's own name for `TestScratch`'s judgement, narrowed to the
    /// journal's prefix. `TestScratchTests` asks it here
    /// (Architecture/BackgroundScans.md § Background scans).
    static func abandonedTestJournals(_ names: [String],
                                      isAlive: (Int32) -> Bool) -> [String] {
        testScratch.abandoned(names, isAlive: isAlive)
    }

    // MARK: - Where things live

    public func directory(module: String) -> URL {
        root.appendingPathComponent(module, isDirectory: true)
    }

    func entriesURL(module: String) -> URL {
        directory(module: module).appendingPathComponent("journal.json")
    }

    func listURL(module: String, _ slot: Slot) -> URL {
        directory(module: module).appendingPathComponent("\(slot.rawValue).json")
    }

    // MARK: - Reading

    /// Newest first, which is the order a page reads them in.
    func entries(module: String) -> [ScanEntry] {
        guard let data = try? Data(contentsOf: entriesURL(module: module)),
              let stored = try? JSONDecoder().decode([ScanEntry].self, from: data)
        else { return [] }
        return stored.sorted { $0.at > $1.at }
    }

    func list(module: String, _ slot: Slot) -> [ScanItem]? {
        guard let data = try? Data(contentsOf: listURL(module: module, slot)) else { return nil }
        return try? JSONDecoder().decode([ScanItem].self, from: data)
    }

    /// What changed between the two lists on disk.
    ///
    /// **A current list that cannot be read is not an empty one.** It is
    /// missing, or corrupt, or a rotation was interrupted between the move and
    /// the write; read as empty, the comparison would report the *entire*
    /// previous list as freed. The nil-is-not-empty distinction of `ScanReport`,
    /// one layer down.
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
    ///
    /// **A refused write is logged.** The rotation has already happened, so a
    /// write that does not land leaves `current` absent, and `change` answers
    /// "nothing is known": no false delta reaches a banner
    /// (`ScanCoordinator.tellSomebodyWhatAppeared` reads back off disk for this
    /// reason). Without the line, a module whose journal never lands would look
    /// like a module with nothing to announce.
    public func record(_ entry: ScanEntry, items: [ScanItem], module: String) {
        writes.sync {
            let directory = self.directory(module: module)
            var landed = PrivateFile.directory(at: directory)

            let current = listURL(module: module, .current)
            let previous = listURL(module: module, .previous)
            if FileManager.default.fileExists(atPath: current.path) {
                try? FileManager.default.removeItem(at: previous)
                try? FileManager.default.moveItem(at: current, to: previous)
            }
            // `&& landed` on the right, so the write always runs: the entries
            // below are worth writing whether or not the list arrived, and
            // `&&` would skip them.
            landed = PrivateFile.write(items, to: current) && landed

            // **The entry just recorded always survives the trim**, so it goes
            // first and the rest follow in date order. Sorting everything and
            // cutting the tail would drop it after a clock that ran fast, or
            // among rows tied on `at` (`Array.sort` is unstable), while the
            // list half of this call has already rotated. It is the newest
            // thing that *happened*, whatever the clock says.
            let older = entries(module: module)
                .filter { $0 != entry }
                .sorted { $0.at > $1.at }
            landed = PrivateFile.write(Array(([entry] + older).prefix(Self.limit)),
                                       to: entriesURL(module: module)) && landed

            guard !landed else { return }
            // The module id, never a path: this file names every file the scan
            // found and the log names none of them.
            HelmLog.shared.warn(module, "the scan journal could not be written — this scan is "
                                + "not in the history, and nothing new will be announced until "
                                + "one lands")
        }
    }
}
