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
                              message: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let flat = message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        return "\(formatter.string(from: date)) [\(level.rawValue)] [\(category)] \(flat)"
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
        guard on else { return }
        write(.info, "app", "Helm \(version) started")
    }

    public func setEnabled(_ on: Bool) {
        queue.async { self.enabled = on }
        if on { write(.info, "app", "logging enabled") }
    }

    public func write(_ level: LogLevel, _ category: String, _ message: String) {
        let line = LogLine.format(date: Date(), level: level, category: category, message: message)
        queue.async {
            guard self.enabled else { return }
            self.append(line + "\n")
        }
    }

    /// Convenience wrappers so call sites read as prose.
    public func info(_ category: String, _ message: String) { write(.info, category, message) }
    public func warn(_ category: String, _ message: String) { write(.warn, category, message) }
    public func error(_ category: String, _ message: String) { write(.error, category, message) }

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
