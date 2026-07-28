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
    ///
    /// `depth` caps the underlying chain. Nothing should be able to make
    /// logging the thing that crashes, and `NSUnderlyingErrorKey` is a
    /// dictionary value: a cycle is possible and would recurse forever.
    public static func describe(_ error: Error, depth: Int = 0) -> String {
        let nsError = error as NSError
        var parts = ["\(nsError.domain) \(nsError.code)"]

        // A Swift enum bridged to NSError loses everything: the associated
        // value is gone and the code is declaration order, which renumbers on
        // the next edit. `InstallError.versionMismatch("0.7.0")` arrived as
        // `… 0 "The operation couldn't be completed"` — which is precisely the
        // uselessness this type was written to end, at the one call site it
        // was written for.
        if !(type(of: error) is NSError.Type) {
            parts.append("(\(oneLine(String(describing: error))))")
        }

        let message = nsError.userInfo[NSLocalizedDescriptionKey] as? String
            ?? nsError.localizedDescription
        if !message.isEmpty { parts.append("“\(oneLine(message))”") }

        if let reason = nsError.localizedFailureReason, !reason.isEmpty {
            parts.append("reason: \(oneLine(reason))")
        }
        // A move failure — and trashing is a move — names its file in a
        // different key from the one a read failure uses.
        for key in [NSFilePathErrorKey, "NSSourceFilePathErrorKey",
                    "NSDestinationFilePathErrorKey"] {
            if let path = nsError.userInfo[key] as? String {
                parts.append("path: \(Redact.path(path))")
                break
            }
        }
        if parts.allSatisfy({ !$0.hasPrefix("path:") }),
           let url = nsError.userInfo[NSURLErrorKey] as? URL {
            parts.append("path: \(Redact.path(url.path))")
        }
        // The reason is nearly always one level down.
        if depth < 4, let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("← \(describe(underlying, depth: depth + 1))")
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

    /// How much of one message is worth keeping.
    ///
    /// `helm.log` rotates at 2 MB and keeps one previous file, so a single
    /// unbounded message can erase the history the log exists to build: a 4 MB
    /// description, twice, and everything before it is gone. No real failure
    /// needs more than this; anything longer is a payload that got into a
    /// message field.
    private static let messageLimit = 800

    /// One event is one line, and the reader is not to be lied to.
    ///
    /// The home path is stripped here rather than at the call sites, because
    /// every string this type emits passes through — including messages, which
    /// carry no key for `Redact.path` to find them by, and which come from
    /// errors Helm has not written yet.
    ///
    /// The line breaks are the obvious half. The rest are the characters a
    /// *reader* obeys: a lone carriage return, U+2028 and U+2029 all break a
    /// line in something, and U+202E reverses everything after it in whatever
    /// the bug report gets pasted into — a log that can be made to misread
    /// itself is worse than one that is merely long.
    private static func oneLine(_ text: String) -> String {
        var flat = text
        for control in ["\r\n", "\n", "\r", "\u{2028}", "\u{2029}",
                        "\u{202A}", "\u{202B}", "\u{202D}", "\u{202E}", "\u{2066}",
                        "\u{2067}", "\u{2068}", "\u{2069}", "\u{200F}", "\u{200E}"] {
            flat = flat.replacingOccurrences(of: control, with: " ")
        }
        // Both spellings, longest first. On an APFS boot volume group every
        // file under the home is reachable a second time as
        // `/System/Volumes/Data` + the same path, which `Redact.path` and the
        // `path:` extraction both answer `~` for. Stripping only the home left
        // `/System/Volumes/Data~/Desktop/…` in the message: no account name in
        // it, and no path either — it says the file is somewhere it is not.
        let home = NSHomeDirectory()
        if !home.isEmpty {
            for spelling in [Redact.FirmlinkTwin.dataMount + home, home] {
                flat = flat.replacingOccurrences(of: spelling, with: "~")
            }
        }
        flat = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > messageLimit else { return flat }
        return flat.prefix(messageLimit) + "… (\(flat.count) characters)"
    }
}

