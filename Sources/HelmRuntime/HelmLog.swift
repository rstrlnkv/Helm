import Foundation
import os

/// Diagnostics for dev builds. Every prerelease ships with the log on: the
/// file is the evidence trail we triage against before a build graduates to
/// the stable channel. Stable builds stay silent unless explicitly opted in.

public enum LogLevel: String, Sendable {
    case info, warn, error
}

/// Whether this build writes a log. Pure so the rule is testable.
public enum LogPolicy {
    public static func isEnabled(version: String, override: Bool?) -> Bool {
        if let override { return override }
        return version.contains("-dev")
    }
}

/// Where the log keeps its files. Pure so the rule is testable, beside the rule
/// about whether there is a log at all.
///
/// **A test process must not write into the file people triage.** The log is a
/// product surface: `~/Library/Logs/Helm/helm.log` is what a dev build is judged
/// by before it ships, so a line in it reads as something the app did. Logging
/// code under test logs — `EngineReply`'s tests exercise the decode failure it
/// was written to record — and those lines wore the shape of a real fault well
/// enough to be triaged as one.
///
/// The *folder* moves rather than the file, because everything that lives beside
/// the log lives beside it by design: the rollover, the purge latch, and
/// `Redact`'s salt. One decision keeps them together, where teaching each of
/// them the same exception separately is how a name ends up spelled twice. It
/// also takes the teeth out of `discardPreRedactionLog`, which deletes the log
/// it finds and has destroyed a dev build's triage evidence once already when a
/// tool that merely linked this target started it.
///
/// The test folder is **one** folder, reused by every run and bounded by the
/// same rollover as the real one — so the file writing stays exercised under
/// test rather than going dark, and nothing accumulates. `ScanJournal` takes one
/// per process and has to sweep after the processes that died; a log has no
/// reason to tell two runs apart, so it does not buy that problem.
public enum LogDestination {

    public static func directory(home: URL, temporary: URL, underTest: Bool) -> URL {
        underTest
            ? temporary.appendingPathComponent("helm-test-logs", isDirectory: true)
            : home.appendingPathComponent("Library/Logs/Helm", isDirectory: true)
    }

    /// What the page's tail is seeded from — the same decision read from the
    /// other side, and it has to be taken here rather than left implied.
    ///
    /// The test folder above is deliberately **one** folder, reused by every run
    /// of every bundle, so that the file writing stays exercised and nothing
    /// accumulates unboundedly. Reading it back makes that shared file part of
    /// every test's tail: `recentEntries()` after a `clearTail()` would answer
    /// with the accumulated history of every run there has ever been — measured
    /// at 46 copies of one line where the test that counted them wanted 1. So a
    /// test process seeds from nothing, and `HelmLog.seed(from:)` is what a test
    /// of the seed hands its own files to.
    static func seedSources(files: [URL], underTest: Bool) -> [URL] {
        underTest ? [] : files
    }
}

/// One event, one line: the file is parsed line-by-line when triaging.
///
/// `LogSeed` is the inverse and the only one — see the rule on that type.
public enum LogLine {
    /// The line an entry would be written as, for anything outside this target
    /// that has to spell one: «Copy log» is the caller, and what it puts on the
    /// pasteboard is the line the file carries rather than a second format
    /// invented at the button. The one that shipped dropped the level, the date
    /// and the source site.
    public static func line(_ entry: LogEntry, timeZone: TimeZone = .current) -> String {
        line(entry, using: stamper(timeZone))
    }

    /// A whole tail of them, on **one** formatter.
    ///
    /// The bulk caller has to exist rather than being a `map` at the call site:
    /// building a `DateFormatter` is the 42.3 µs ARCHITECTURE.md § What is
    /// running already records — the 42 ms hitch «Copy log» paid on a full tail
    /// before `HelmDates` cached its own — and this one carries a time zone as
    /// well, which measured 77–100 µs on 2026-08-14. A thousand of them is a
    /// tenth of a second on the main thread for one press of a button.
    public static func lines(_ entries: [LogEntry], timeZone: TimeZone = .current) -> String {
        let formatter = stamper(timeZone)
        return entries.map { line($0, using: formatter) }.joined(separator: "\n")
    }

    /// The stamp every line opens with, spelled once.
    ///
    /// `LogSeed` reads it back and needs the same pattern to the character —
    /// two spellings of it are the drift this repository names as a defect of
    /// its own: one side changes and nothing is an error anywhere. It is also
    /// what makes the seed's fixed-width arithmetic legitimate.
    static let stampFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    static func stamper(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = stampFormat
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    /// The five parts as they were always spelled, for a caller holding parts
    /// rather than an entry.
    static func format(date: Date, level: LogLevel, category: String,
                       message: String, site: LogSite? = nil,
                       timeZone: TimeZone = .current) -> String {
        line(LogEntry(date: date, level: level, category: category, message: message, site: site),
             using: stamper(timeZone))
    }

    /// The one place a line is spelled. An entry rather than five parameters,
    /// because the five parts of a line *are* a `LogEntry` — carrying them
    /// separately alongside the type that holds them is how the tail came to be
    /// missing one of them.
    private static func line(_ entry: LogEntry, using formatter: DateFormatter) -> String {
        let flat = entry.message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        // The site goes last: the message is what you read, the place is what
        // you need once you have decided to look.
        let where_ = entry.site.map { "  (\($0.description))" } ?? ""
        return "\(formatter.string(from: entry.date)) [\(entry.level.rawValue)] "
            + "[\(entry.category)] \(flat)\(where_)"
    }
}

enum LogRotation {
    /// Rotate once the file has reached the limit, not before.
    static func shouldRotate(currentSize: Int, limit: Int) -> Bool {
        currentSize >= limit
    }
}

/// The file-backed logger. Writes are serialized on a private queue so any
/// thread can log without blocking the caller on IO.
public final class HelmLog: @unchecked Sendable {
    public static let shared = HelmLog()

    /// Guarded by its own queue rather than the log's: the log's queue is where
    /// lines are written, and a reading must not wait behind a file rotation.
    private var footprint = FootprintTracker()
    private let footprintQueue = DispatchQueue(label: "helm.log.footprint")

    /// ~/Library/Logs/Helm/helm.log — the place macOS users (and Console.app)
    /// expect app logs to live. Somewhere else entirely under test; the reason
    /// is on `LogDestination`.
    ///
    /// Resolved once. Every appended line asks for this folder, and none of the
    /// three answers it is built from can change while the process lives.
    public static let directory: URL =
        LogDestination.directory(home: FileManager.default.homeDirectoryForCurrentUser,
                                 temporary: FileManager.default.temporaryDirectory,
                                 underTest: TestProcess.isRunning)
    public static var fileURL: URL { directory.appendingPathComponent("helm.log") }
    /// Where rollover puts the old half.
    ///
    /// Declared, because it used to be spelled twice and the two spellings did
    /// not match: the one-time purge of the pre-redaction log removed
    /// `helm.log.1`, a name rotation has never written. The half of the log that
    /// most needed destroying — VPN names, application names, home paths —
    /// survived both the purge and the Clear button.
    public static var previousFileURL: URL {
        directory.appendingPathComponent("helm.previous.log")
    }
    /// Everything the log can leave on disk. Anything that clears the log
    /// clears all of it.
    public static var allFileURLs: [URL] { [fileURL, previousFileURL] }
    /// The same two, oldest half first, and none of them under test — the reason
    /// is on `LogDestination.seedSources`.
    static var seedSources: [URL] {
        LogDestination.seedSources(files: [previousFileURL, fileURL],
                                   underTest: TestProcess.isRunning)
    }
    /// The latch for the one-time pre-redaction purge.
    ///
    /// Deliberately **not** in `allFileURLs`: it is the record that the purge
    /// happened, so a purge that removed it would be able to run again. Named
    /// here rather than inside the purge because a file name invented in a
    /// second place is the exact defect `LogFileNamesTests` was written for.
    public static var resetMarkerURL: URL {
        directory.appendingPathComponent(".redaction-reset")
    }
    private static let sizeLimit = 2 * 1024 * 1024   // 2 MB, then one rollover

    private let queue = DispatchQueue(label: "helm.log", qos: .utility)
    private var enabled = false
    /// The files the first `recentEntries()` reads back — this process's two, in
    /// the order they happened.
    ///
    /// Held per instance rather than taken from the static at the moment of the
    /// read, because under test the honest answer is *no files at all*
    /// (`LogDestination.seedSources`) — so a log built with files of its own is
    /// the only way the first read can be exercised, and the first read is the
    /// whole of this. `shared` is the one instance the app has, and `init` is
    /// internal, so nothing outside this target can make a second.
    private let seedFiles: [URL]

    init(seedFiles: [URL] = HelmLog.seedSources) {
        self.seedFiles = seedFiles
    }

    /// Called once at launch with the running version; `override` comes from
    /// the user-facing switch (nil = follow the build type).
    public func start(version: String, override: Bool?) {
        let on = LogPolicy.isEnabled(version: version, override: override)
        queue.async { self.enabled = on }
        discardPreRedactionLog()
        // Once a launch, not once a line. `append` creates the file privately,
        // but a file an earlier build created keeps its 0644 for ever otherwise —
        // which is what `~/Library/Logs/Helm/helm.log` was measured at, inside
        // the 0700 folder that was doing all of the protecting.
        // Discarded: `harden` answers whether there was a file to tighten, and
        // "there was not" is the ordinary case — this runs before the first line
        // is written, and the paragraph above says so.
        queue.async { Self.allFileURLs.forEach { _ = PrivateFile.harden(at: $0) } }
        guard on else { return }
        write(.info, "app", "Helm \(version) started")
    }

    /// Throws away a log written before `Redact` existed.
    ///
    /// Adding redaction stopped new lines from naming VPN connections, apps and
    /// home paths; it did nothing about the ones already on disk, and there is
    /// a "Copy log" button whose whole purpose is pasting that file into a bug
    /// report. Two megabytes of rollover could take weeks to clear it. Once.
    ///
    /// **The latch is a file beside the log, not a preference.** It used to be
    /// `UserDefaults.standard`, which is the *calling process's* domain — so
    /// "once" meant once per process identity, and any tool that links
    /// HelmRuntime and starts the log deleted the user's log the first time it
    /// ran. That is not hypothetical: it destroyed a dev build's triage
    /// evidence, which is the one thing this file exists to hold.
    private func discardPreRedactionLog() {
        let marker = Self.resetMarkerURL
        let fm = FileManager.default
        guard !fm.fileExists(atPath: marker.path) else { return }
        queue.async {
            for url in Self.allFileURLs { try? fm.removeItem(at: url) }
            // Discarded: the `createFile` below is what this block is for and it
            // has its own answer; a folder that could not be made is a marker
            // that cannot land, and an unlanded marker retries at the next
            // launch — which is a repeated deletion of a log that is already
            // empty. See `append` for why nothing here can be logged.
            _ = PrivateFile.directory(at: Self.directory)
            fm.createFile(atPath: marker.path, contents: Data())
        }
    }

    /// Both edges are written, and the off edge is written **before** the flag
    /// moves: a file that simply stops cannot be told from an app that died, and
    /// «the person switched it off» is the commonest reason of the two.
    public func setEnabled(_ on: Bool) {
        if !on { write(.info, "app", "logging disabled") }
        queue.async { self.enabled = on }
        if on { write(.info, "app", "logging enabled") }
    }

    /// The last lines, for a dev build that wants to watch them arrive rather
    /// than open the file afterwards. Guarded by the same queue as the file, so
    /// a reader never sees a half-written line.
    private var tail = LogTail()
    /// The file has been read once. It is read at the first `recentEntries()`
    /// rather than at launch: nothing but the page asks, and a launch that reads
    /// two megabytes for a window nobody opened is a cost paid by everybody.
    private var seeded = false

    /// A snapshot, oldest first. Taken on the queue and handed back by value:
    /// the page that draws it must not hold anything the logger is still
    /// writing to.
    ///
    /// **The first call reads the file.** Until 2026-08-14 this answered with
    /// what *this process* had written since launch, which on the owner's own
    /// machine was 45 lines of a 5 306-line log — so the page called Log showed
    /// 0.85 % of it under a footer that read as the whole thing, and the event
    /// somebody opened it for was almost never there.
    public func recentEntries() -> [LogEntry] {
        queue.sync {
            if !seeded {
                seeded = true
                seedLocked(from: seedFiles)
            }
            return tail.entries
        }
    }

    private func seedLocked(from urls: [URL]) {
        let onDisk = LogSeed.read(urls, atMost: Self.seedByteLimit, limit: tail.limit)
        tail.replace(with: LogSeed.seeded(file: onDisk, live: tail.entries, limit: tail.limit))
    }

    /// How much of each file the seed reads, against the two megabytes reading
    /// the whole of it would cost for a page showing its end.
    ///
    /// Measured on the owner's log, 2026-08-14: 5 327 lines in 396 912 bytes,
    /// and its newest thousand lines 76 460 of them — so a quarter of a megabyte
    /// is that thousand three times over. A bound in bytes and not in lines,
    /// because bytes are what the read costs; a log of unusually wide lines (the
    /// widest here is 540 characters) seeds fewer than a thousand rather than
    /// reading more, which is the direction for this to fail in.
    private static let seedByteLimit = 256 * 1024

    /// Whether there is a log on disk at all — the question «Clear» is drawn
    /// from, asked of the file system every time rather than remembered, because
    /// the file can go without this process doing it.
    public static func anyFileExists(among urls: [URL] = allFileURLs) -> Bool {
        urls.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func clearTail() {
        queue.async { self.tail.clear() }
    }

    public func write(_ level: LogLevel, _ category: String, _ message: String,
                      site: LogSite? = nil) {
        // The timestamp is taken here, where the event happened; the line is
        // built on the queue, after the check. Formatting allocates a
        // DateFormatter and walks the string twice, and on a beta build every
        // one of those was discarded a moment later.
        let now = Date()
        queue.async {
            guard self.enabled else { return }
            // The tail is filled from the same parts the line is spelled from,
            // not by parsing the line back apart — one value handed to both, so
            // they are the same five parts by construction rather than by two
            // call sites agreeing. (`LogSeed` is the one place a line is read
            // back, and it is for the file this process did not write.)
            let entry = LogEntry(date: now, level: level, category: category,
                                 message: message, site: site)
            self.tail.append(entry)
            self.append(LogLine.line(entry) + "\n")
        }
    }

    /// Convenience wrappers so call sites read as prose.
    ///
    /// `warn` and `error` capture where they were called from: the wording of
    /// a failure is what reaches a bug report, and the same wording can come
    /// from four places. `info` does not — it describes an event, not a fault,
    /// and the file it came from is noise on every line of a healthy log.
    public func info(_ category: String, _ message: String) {
        write(.info, category, message)
    }

    /// What an operation cost, against the last reading for the same label.
    ///
    /// Silent when the kernel will not answer and silent when nothing moved:
    /// a diagnostic that writes a line per event is a diagnostic nobody reads.
    /// The threshold and the accounting live in `FootprintTracker` — this only
    /// decides that memory is worth a category of its own, because "which of
    /// these two hundred lines is about memory" is the question being asked
    /// when someone opens the log for this.
    public func memory(_ label: String) {
        guard let bytes = MemoryFootprint.current() else { return }
        // Captured here, not on the queue: by the time the write happens the
        // phase may be over, and a figure is worth having only beside what was
        // running when it was taken.
        // The timer sample asks about everything; a phase asks about everything
        // *else*, because it is the one thing it already knows.
        let isSample = label == "sample" || label == "launch"
        let doing = HelmActivity.describe(HelmActivity.running,
                                          excluding: isSample ? nil : label)
        footprintQueue.async {
            guard let report = self.footprint.report(label, bytes: bytes) else { return }
            let beside = doing.isEmpty ? "" : " — \(doing)"
            self.write(.info, "memory", "\(report.label): \(report.line)\(beside)")
        }
    }

    /// What a bounded scope cost, from two readings taken around it.
    ///
    /// Different question from `memory(_:)`, which reports a running total against
    /// the last sighting of the same label and stays quiet below 8 MB. Here the
    /// cost *is* the question — building a module, tearing one down — the figure is
    /// single-digit megabytes, and being small is the answer rather than a reason
    /// to withhold it. Same `memory` category, so one filter still finds
    /// everything about memory.
    public func memory(_ label: String, grewBy bytes: Int) {
        write(.info, "memory", "\(label): \(ScopeCost.line(grewBy: bytes))")
    }

    public func warn(_ category: String, _ message: String,
                     fileID: String = #fileID, line: Int = #line,
                     function: String = #function) {
        write(.warn, category, message,
              site: LogSite(fileID: fileID, line: line, function: function))
    }

    public func error(_ category: String, _ message: String,
                      fileID: String = #fileID, line: Int = #line,
                      function: String = #function) {
        write(.error, category, message,
              site: LogSite(fileID: fileID, line: line, function: function))
    }

    /// The common shape: something threw, and the thrown thing is the report.
    public func failure(_ category: String, _ what: String, _ error: Error,
                        fileID: String = #fileID, line: Int = #line,
                        function: String = #function) {
        write(.error, category, "\(what): \(HelmFailure.describe(error))",
              site: LogSite(fileID: fileID, line: line, function: function))
    }

    public func clear() {
        queue.async {
            // All of it. Clearing only `helm.log` left the rollover behind, so
            // the button said the log was gone while up to two megabytes of it
            // sat beside the file it had just emptied.
            for url in Self.allFileURLs { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: - IO (always on the private queue)

    /// **A log that cannot write cannot log that it cannot write**, which is why
    /// the only refusal in this file goes somewhere else.
    ///
    /// Every other caller of `PrivateFile` in the app answers a refusal with a
    /// line here. This one cannot: the line would be appended by the call that
    /// just failed, and a line about the failure would fail in turn, on the
    /// queue that is already running the first one. A flag saying «the file is
    /// unwritable» would be worse than silence — it is the family this house has
    /// a name for, a local boolean standing in for a live external fact, with
    /// nothing to tell it the disk came back.
    ///
    /// Two things are true instead. `LogView`'s tail already has the line: it is
    /// appended in `write` before this runs, so the surface a person can open is
    /// unaffected and only the *file* — the one "Copy log" hands to a bug report
    /// — is missing what the screen is showing. And `os.Logger` is a different
    /// port on a different store, so the refusal is said in the unified log,
    /// where `log show --predicate 'subsystem == "com.helm.app"'` finds it. Not
    /// rate-limited by hand: the system does that, and the alternative to some
    /// noise while a disk is full is a log that quietly stops.
    private func append(_ text: String) {
        let url = Self.fileURL
        // On every append: the folder may predate this rule, and `attributes:`
        // on a create call only covers a folder that call made. The log is
        // diagnostic, not public — no other account needs to read it.
        //
        // Discarded: a folder that could not be made is a write that cannot
        // land, and the writes below report for both.
        _ = PrivateFile.directory(at: Self.directory)
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()).map(Int.init) ?? 0
            if LogRotation.shouldRotate(currentSize: size, limit: Self.sizeLimit) {
                try? handle.close()
                rotate()
                // Both branches that *create* the file go through `PrivateFile`:
                // a bare write takes the umask, which is 0644 here, and the file
                // then keeps it for as long as it is appended to.
                if !PrivateFile.write(data, to: url) { Self.sayOutOfBand() }
                return
            }
            try? handle.write(contentsOf: data)
        } else if !PrivateFile.write(data, to: url) {
            Self.sayOutOfBand()
        }
    }

    /// The one channel left when the log's own file is the thing refusing.
    ///
    /// No path and no message text: this says that the file is not taking lines,
    /// and the lines it is not taking are the ones that carry Helm's redaction.
    /// Sending them through a second store would be handing the unified log
    /// content that was written for a file with a `0600` mode on it.
    private static func sayOutOfBand() {
        // One literal and no interpolation: `Logger` takes an `OSLogMessage`,
        // which a concatenation is not, and there is nothing here to interpolate.
        outOfBand.error("the diagnostics log could not be written; this session's lines are in the app's live log view only, and not in the file Copy log hands over")
    }

    private static let outOfBand = Logger(subsystem: "com.helm.app", category: "log")

    private func rotate() {
        let fm = FileManager.default
        try? fm.removeItem(at: Self.previousFileURL)
        try? fm.moveItem(at: Self.fileURL, to: Self.previousFileURL)
    }
}
