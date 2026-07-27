import Foundation
import os

/// Diagnostics for dev builds. Every prerelease ships with the log on: the
/// file is the evidence trail we triage against before a build graduates to
/// the stable channel. Stable builds stay silent unless explicitly opted in.

public enum LogLevel: String, Sendable {
    case debug, info, warn, error
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

    /// ~/Library/Logs/Helm/helm.log — the place macOS users (and Console.app)
    /// expect app logs to live.
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Helm", isDirectory: true)
    }
    public static var fileURL: URL { directory.appendingPathComponent("helm.log") }
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
    private func discardPreRedactionLog() {
        let key = "module.app.logRedactionReset"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        queue.async {
            let fm = FileManager.default
            try? fm.removeItem(at: Self.fileURL)
            try? fm.removeItem(at: Self.directory.appendingPathComponent("helm.log.1"))
        }
    }

    public func setEnabled(_ on: Bool) {
        queue.async { self.enabled = on }
        if on { write(.info, "app", "logging enabled") }
    }

    public func write(_ level: LogLevel, _ category: String, _ message: String,
                      site: LogSite? = nil) {
        let line = LogLine.format(date: Date(), level: level, category: category,
                                  message: message, site: site)
        queue.async {
            guard self.enabled else { return }
            self.append(line + "\n")
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

    /// The current log, newest last — used by the in-app diagnostics view.
    public func currentText(maxBytes: Int = 256 * 1024) -> String {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return "" }
        let tail = data.count > maxBytes ? data.suffix(maxBytes) : data
        return String(decoding: tail, as: UTF8.self)
    }

    public func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: Self.fileURL)
        }
    }

    // MARK: - IO (always on the private queue)

    private func append(_ text: String) {
        let fm = FileManager.default
        let url = Self.fileURL
        if !fm.fileExists(atPath: Self.directory.path) {
            try? fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        }
        // 0700 explicitly, and on every append: the folder may predate this
        // rule, and `attributes:` above would only cover a folder created here.
        // The log is diagnostic, not public — no other account needs to read it.
        try? fm.setAttributes([.posixPermissions: 0o700],
                              ofItemAtPath: Self.directory.path)
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
        let previous = Self.directory.appendingPathComponent("helm.previous.log")
        try? fm.removeItem(at: previous)
        try? fm.moveItem(at: Self.fileURL, to: previous)
    }
}
