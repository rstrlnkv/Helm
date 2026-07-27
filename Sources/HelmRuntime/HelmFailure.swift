import Foundation
import Security

/// Where a log line came from.
///
/// Four call sites can produce the same wording, and the wording is what a
/// bug report carries. `#fileID` and `#line` cost nothing at the call site and
/// turn "refused out-of-scope path" into a place in the source.
public struct LogSite: Sendable, Equatable {
    public let file: String
    public let line: Int
    public let function: String

    public init(file: String, line: Int, function: String) {
        self.file = file
        self.line = line
        self.function = function
    }

    /// `#fileID` is "ModuleName/File.swift". The module is already the log's
    /// category, so only the filename is kept.
    public init(fileID: String, line: Int, function: String) {
        self.file = fileID.split(separator: "/").last.map(String.init) ?? fileID
        self.line = line
        self.function = function
    }

    public var description: String { "\(file):\(line) \(function)" }
}

/// Turns a failure into something worth writing down.
///
/// The log used to record `error.localizedDescription`, which for a Cocoa
/// error is usually "The operation couldn’t be completed." — the domain, the
/// code, the failing path and the underlying error all discarded, and the
/// underlying error is nearly always the answer. OSStatus went in as a bare
/// integer: a number to paste into a search engine rather than a fact.
///
/// Everything here is redacted on the way through: a path is the most useful
/// thing in a failure and the most private, so it goes in as `~/Documents/…`
/// rather than not at all.
public enum HelmFailure {

    /// Domain, code, message, failing path and underlying cause — as much as
    /// the error actually carries, on one line.
    public static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = ["\(nsError.domain) \(nsError.code)"]

        let message = nsError.userInfo[NSLocalizedDescriptionKey] as? String
            ?? nsError.localizedDescription
        if !message.isEmpty { parts.append("“\(oneLine(message))”") }

        if let reason = nsError.localizedFailureReason, !reason.isEmpty {
            parts.append("reason: \(oneLine(reason))")
        }
        if let path = nsError.userInfo[NSFilePathErrorKey] as? String {
            parts.append("path: \(Redact.path(path))")
        } else if let url = nsError.userInfo[NSURLErrorKey] as? URL {
            parts.append("path: \(Redact.path(url.path))")
        }
        // The reason is nearly always one level down.
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("← \(describe(underlying))")
        }
        return parts.joined(separator: " ")
    }

    /// An OSStatus with whatever name macOS knows for it. Security codes have
    /// messages; most others do not, and then the number is at least labelled.
    public static func osStatus(_ status: Int32) -> String {
        let text = securityMessage(status)
        return text.map { "OSStatus \(status) “\(oneLine($0))”" } ?? "OSStatus \(status)"
    }

    /// nil for `noErr`, so a call site can log only when there is something to
    /// log: `if let failure = HelmFailure.osStatusIfFailed(status) { … }`.
    public static func osStatusIfFailed(_ status: Int32) -> String? {
        status == 0 ? nil : osStatus(status)
    }

    /// A POSIX errno, named. `2` is nothing; `ENOENT (2) No such file or
    /// directory` is a diagnosis.
    public static func posix(_ code: Int32) -> String {
        let text = String(cString: strerror(code))
        return "errno \(code) “\(oneLine(text))”"
    }

    // MARK: -

    private static func securityMessage(_ status: Int32) -> String? {
        guard let cf = SecCopyErrorMessageString(status, nil) else { return nil }
        let text = cf as String
        // macOS answers an unknown code with a restatement of the number,
        // which adds nothing the caller did not already have.
        return text.contains("\(status)") && text.count < 24 ? nil : text
    }

    /// One event is one line: the log is triaged with grep.
    private static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

