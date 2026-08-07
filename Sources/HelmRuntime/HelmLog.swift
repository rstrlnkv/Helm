import Foundation

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

/// One event, one line: the file is parsed line-by-line when triaging.
public enum LogLine {
    public static func format(date: Date, level: LogLevel, category: String,
                              message: String, site: LogSite? = nil,
                              timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let flat = message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        // The site goes last: the message is what you read, the place is what
        // you need once you have decided to look.
        let where_ = site.map { "  (\($0.description))" } ?? ""
        return "\(formatter.string(from: date)) [\(level.rawValue)] [\(category)] \(flat)\(where_)"
    }
}

public enum LogRotation {
    /// Rotate once the file has reached the limit, not before.
    public static func shouldRotate(currentSize: Int, limit: Int) -> Bool {
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
    /// expect app logs to live.
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Helm", isDirectory: true)
    }
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

    private init() {}

    /// Called once at launch with the running version; `override` comes from
    /// the user-facing switch (nil = follow the build type).
    public func start(version: String, override: Bool?) {
        let on = LogPolicy.isEnabled(version: version, override: override)
        queue.async { self.enabled = on }
        discardPreRedactionLog()
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
            PrivateFile.directory(at: Self.directory)
            fm.createFile(atPath: marker.path, contents: Data())
        }
    }

    public func setEnabled(_ on: Bool) {
        queue.async { self.enabled = on }
        if on { write(.info, "app", "logging enabled") }
    }

    /// The last lines, for a dev build that wants to watch them arrive rather
    /// than open the file afterwards. Guarded by the same queue as the file, so
    /// a reader never sees a half-written line.
    private var tail = LogTail()

    /// A snapshot, oldest first. Taken on the queue and handed back by value:
    /// the page that draws it must not hold anything the logger is still
    /// writing to.
    public func recentEntries() -> [LogEntry] {
        queue.sync { tail.entries }
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
            // not by parsing the line back apart.
            self.tail.append(LogEntry(date: now, level: level, category: category,
                                      message: message))
            self.append(LogLine.format(date: now, level: level, category: category,
                                       message: message, site: site) + "\n")
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

    private func append(_ text: String) {
        let fm = FileManager.default
        let url = Self.fileURL
        // On every append: the folder may predate this rule, and `attributes:`
        // on a create call only covers a folder that call made. The log is
        // diagnostic, not public — no other account needs to read it.
        PrivateFile.directory(at: Self.directory)
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()).map(Int.init) ?? 0
            if LogRotation.shouldRotate(currentSize: size, limit: Self.sizeLimit) {
                try? handle.close()
                rotate()
                try? data.write(to: url)
                return
            }
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    private func rotate() {
        let fm = FileManager.default
        try? fm.removeItem(at: Self.previousFileURL)
        try? fm.moveItem(at: Self.fileURL, to: Self.previousFileURL)
    }
}
