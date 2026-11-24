import Foundation

/// Reading the log back — **the one place in this app a log line is parsed.**
///
/// The tail is filled from the parts a line is spelled from, never by parsing
/// the line back (Architecture/DiagnosticsLog.md § The log pane). A *seed* has
/// no parts to hold, so it parses, here, as the exact inverse of `LogLine.line`.
/// `ThePageShowsTheLogAndNotTheSessionTests` holds the round trip.
///
/// **A line it cannot read is kept whole and claims nothing.** Dropping it would
/// hide the half-written line a crash left behind, and guessing at its parts
/// would put a level and a module on text the app did not write. The whole line
/// becomes the message, the category is empty, the level is `info`, and the
/// date is the one on the line above it.
///
/// `Redact` runs before `write`, so a parse cannot bring back a name the file
/// never held. The clock can be wrong: the file spells local time and no
/// offset, so lines written in another time zone are drawn at their wall-clock
/// time. The alternative is discarding them.
public enum LogSeed {

    /// How many characters a stamp is: whatever `LogLine.stampFormat` spells.
    fileprivate static let stampLength = LogLine.stampFormat.count

    /// What one line of the file turned back into.
    enum Line: Equatable {
        case entry(LogEntry)
        /// Not a line this app wrote, or not all of one.
        case unreadable(String)
    }

    /// The stamp `LogLine.line` writes, read the other way — and read once a
    /// minute rather than once a line.
    ///
    /// `DateFormatter.date(from:)` costs tens of microseconds, so a thousand
    /// lines parsed the plain way is a visible stall on the main thread when the
    /// page opens. A thousand lines span minutes, not seconds, so the minute is
    /// remembered and the seconds and milliseconds are arithmetic on it.
    ///
    /// A minute rather than a day because a zone offset can change inside a day
    /// and not inside a minute; the arithmetic is only safe under a constant
    /// offset.
    final class Stamps {
        private let formatter: DateFormatter
        private var minute = ""
        private var minuteStarted = Date.distantPast

        /// `LogLine`'s own formatter, never a second spelling of its pattern:
        /// the widths this class counts on (23 characters, seconds at 17,
        /// milliseconds at 20) are that pattern's, and a format changed on one
        /// side only would leave every line unreadable with nothing to say so.
        init(timeZone: TimeZone = .current) {
            formatter = LogLine.stamper(timeZone)
        }

        /// Exactly `yyyy-MM-dd HH:mm:ss.SSS`, or nothing: a stamp of another
        /// width is a line this app did not write, and the caller keeps it whole.
        func date(from stamp: Substring) -> Date? {
            guard stamp.count == LogSeed.stampLength,
                  let seconds = Int(stamp.dropFirst(17).prefix(2)),
                  let millis = Int(stamp.suffix(3))
            else { return nil }
            let head = String(stamp.prefix(16))
            if head != minute {
                guard let start = formatter.date(from: head + ":00.000") else { return nil }
                minute = head
                minuteStarted = start
            }
            return minuteStarted.addingTimeInterval(Double(seconds) + Double(millis) / 1000)
        }
    }

    /// `2026-08-14 13:32:01.123 [warn] [layout] message  (File.swift:12 f())`
    ///
    /// The formatter is passed in and never defaulted: one per read, not one per
    /// line, since building a `DateFormatter` per line costs more than the parse
    /// the minute cache saves.
    static func parse(_ line: String, using formatter: Stamps) -> Line {
        var rest = Substring(line)
        guard let stamp = take(&rest, upTo: " ["), let date = formatter.date(from: stamp),
              // «] [» rather than «] », because a level is one word and a message
              // is not: taking the first «] » would find one inside the message
              // of a line whose category had already gone missing.
              let level = take(&rest, upTo: "] [").flatMap({ LogLevel(rawValue: String($0)) }),
              let category = take(&rest, upTo: "] ")
        else { return .unreadable(line) }
        let (message, site) = splitSite(String(rest))
        return .entry(LogEntry(date: date, level: level, category: String(category),
                               message: message, site: site))
    }

    /// The site `LogLine.line` puts last, and only when the tail really has its
    /// shape: two spaces, then `Name.swift:123 function(…)` in brackets at the very
    /// end. A message ending in «(exit 2)» keeps its brackets — `HelmFailure`
    /// writes those, and stealing them would be inventing a source location.
    private static func splitSite(_ message: String) -> (String, LogSite?) {
        guard message.hasSuffix(")"), let opened = message.range(of: "  (", options: .backwards)
        else { return (message, nil) }
        let inside = message[opened.upperBound..<message.index(before: message.endIndex)]
        guard let space = inside.firstIndex(of: " ") else { return (message, nil) }
        let place = inside[inside.startIndex..<space]
        let function = inside[inside.index(after: space)...]
        guard let colon = place.lastIndex(of: ":"), !function.isEmpty,
              let number = Int(place[place.index(after: colon)...])
        else { return (message, nil) }
        return (String(message[message.startIndex..<opened.lowerBound]),
                LogSite(file: String(place[place.startIndex..<colon]), line: number,
                        function: String(function)))
    }

    /// Everything before `separator`, moving the cursor past it. Nil when the
    /// separator is not there, which is how every malformed line leaves.
    private static func take(_ rest: inout Substring, upTo separator: String) -> Substring? {
        guard let found = rest.range(of: separator) else { return nil }
        let head = rest[rest.startIndex..<found.lowerBound]
        rest = rest[found.upperBound...]
        return head
    }

    /// A file's worth of lines, oldest first.
    ///
    /// - Parameters:
    ///   - startedMidFile: the read began at an offset, so the first line is a
    ///     fragment of one the reader cut rather than one anything tore. That one
    ///     is the reader's own doing and goes; every other unreadable line stays.
    ///   - fallback: the date for an unreadable line when no line in the text is
    ///     readable at all — the file's own modification date, never now. An
    ///     unreadable line above the first readable one takes that line's date
    ///     instead, so it opens no day of its own.
    ///   - limit: how many lines are wanted, dropped **before** the parse rather
    ///     than after it: the byte window holds several times what the tail
    ///     keeps.
    static func entries(from text: String, startedMidFile: Bool, dated fallback: Date,
                        keepingLast limit: Int = .max,
                        using formatter: Stamps) -> [LogEntry] {
        var lines = text.components(separatedBy: "\n")
        if startedMidFile, !lines.isEmpty { lines.removeFirst() }
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        var out: [LogEntry] = []
        var last = fallback
        // Unreadable lines with no readable line above them yet. They are kept
        // whole and dated once a readable line below them says what day the
        // file was on; until then the fallback would be the newest moment in the
        // file and would head it with a day none of its lines was written on.
        var leading: [String] = []
        for line in lines where !line.isEmpty {
            switch parse(line, using: formatter) {
            case .entry(let entry):
                out += leading.map { LogEntry(date: entry.date, level: .info, category: "", message: $0) }
                leading.removeAll()
                last = entry.date
                out.append(entry)
            case .unreadable(let text):
                if out.isEmpty { leading.append(text) }
                else { out.append(LogEntry(date: last, level: .info, category: "", message: text)) }
            }
        }
        // Nothing in the text was readable: the caller's date is all there is.
        out += leading.map { LogEntry(date: fallback, level: .info, category: "", message: $0) }
        return out
    }

    /// The file and this process as one list.
    ///
    /// The file already holds every line this process has written, so a seed that
    /// simply prepended it would show each of them twice. What is taken is what
    /// came before the oldest line in hand — `prefix(while:)` and not `filter`,
    /// because the file is in the order it happened and a clock that went
    /// backwards must not let a later line back in.
    static func seeded(file: [LogEntry], live: [LogEntry], limit: Int) -> [LogEntry] {
        guard let first = live.first else { return Array(file.suffix(limit)) }
        return Array((file.prefix { $0.date < first.date } + live).suffix(limit))
    }

    /// The last `bytes` of each file, in the order given — the rolled-over half
    /// first, then the one being written.
    ///
    /// Bounded by bytes as well as by lines, so a page opened to read the end of
    /// the file does not hold all of it. A read that starts at an offset says so,
    /// so the fragment it lands in is dropped rather than drawn.
    static func read(_ urls: [URL], atMost bytes: Int, limit: Int,
                     using formatter: Stamps = Stamps()) -> [LogEntry] {
        var out: [LogEntry] = []
        for url in urls {
            autoreleasepool {
                guard let handle = try? FileHandle(forReadingFrom: url) else { return }
                defer { try? handle.close() }
                let size = (try? handle.seekToEnd()).map(Int.init) ?? 0
                let offset = max(0, size - bytes)
                try? handle.seek(toOffset: UInt64(offset))
                guard let data = try? handle.readToEnd() else { return }
                // Decoded, not validated: a read cut inside a multi-byte character
                // leaves bytes that are not UTF-8 in the first fragment (dropped
                // below) and a tear in the last line (kept), and 0x0A never occurs
                // inside a sequence, so no other line is touched. `String(data:)`
                // would answer nil for the whole file.
                let text = String(decoding: data, as: UTF8.self)
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let modified = attributes?[.modificationDate] as? Date
                out += entries(from: text, startedMidFile: offset > 0,
                               dated: modified ?? Date(timeIntervalSince1970: 0),
                               keepingLast: limit, using: formatter)
            }
        }
        return Array(out.suffix(limit))
    }
}

/// **Recognising the launch words.** `HelmLog` writes them through `LogLine`;
/// these read them back from the same words. `TheLogSplitsIntoLaunchesTests`
/// holds the two together: a reworded line would turn every card into one long
/// "earlier launch".
extension LogSeed {

    /// The version a start line names, or nil for any other line.
    ///
    /// **A start line a crash glued to a torn one is still a start.** A write cut
    /// short has no newline, so the next launch's first line is appended to it
    /// and read as one entry. The launch after a crash is the one somebody opened
    /// the page for, so it is read as a launch; the entry stays one line.
    public static func version(of entry: LogEntry) -> String? {
        if entry.category == LogLine.appCategory, let version = version(inMessage: entry.message) {
            return version
        }
        return versionOfGluedStart(entry)
    }

    private static func isAppLine(_ entry: LogEntry, _ message: String) -> Bool {
        entry.category == LogLine.appCategory && entry.message == message
    }

    public static func isTerminating(_ entry: LogEntry) -> Bool {
        isAppLine(entry, LogLine.terminating)
    }

    public static func isLoggingDisabled(_ entry: LogEntry) -> Bool {
        isAppLine(entry, LogLine.loggingDisabled)
    }

    public static func isBareLoggingEnabled(_ entry: LogEntry) -> Bool {
        isAppLine(entry, LogLine.loggingEnabledWord)
    }

    /// `.some(nil)` for a bare «logging enabled» (older builds wrote no version),
    /// `.some(version)` for «logging enabled (version)», nil for any other line.
    public static func loggingEnabled(_ entry: LogEntry) -> String?? {
        guard entry.category == LogLine.appCategory else { return nil }
        let word = LogLine.loggingEnabledWord
        if entry.message == word { return .some(nil) }
        guard entry.message.hasPrefix(word + " ("), entry.message.hasSuffix(")") else { return nil }
        return .some(String(entry.message.dropFirst(word.count + 2).dropLast()))
    }
}

extension LogSeed {

    /// The glued pair, whatever byte the tear fell on and whatever level the
    /// torn line had. `LogSeed` reads the pair as a stamp-level-category-message
    /// entry when it can and as one whole unreadable message when it cannot, so
    /// the two are put back into one string — category, «] », message — and the
    /// start line is looked for at the end of it: its own stamp, «[info] [app]
    /// Helm … started». A start line standing alone has category `app` and was
    /// answered before this is asked.
    ///
    /// **Not a line that carries a source site.** A glued start ends with the
    /// start line, which has no site, so a warning or an error that merely
    /// quotes a start line is not a launch. An `info` line quoting one cannot be
    /// told from a tear by the entry alone.
    fileprivate static func versionOfGluedStart(_ entry: LogEntry) -> String? {
        guard entry.site == nil, entry.message.hasSuffix(LogLine.startedSuffix) else { return nil }
        let text = entry.category.isEmpty ? entry.message : entry.category + "] " + entry.message
        let marker = " [info] [\(LogLine.appCategory)] \(LogLine.startedPrefix)"
        guard let found = text.range(of: marker, options: .backwards),
              text.distance(from: text.startIndex, to: found.lowerBound) >= stampLength,
              isStamp(text[text.index(found.lowerBound, offsetBy: -stampLength)..<found.lowerBound])
        else { return nil }
        return version(inMessage: String(text[text.index(found.upperBound, offsetBy: -LogLine.startedPrefix.count)...]))
    }

    fileprivate static func version(inMessage message: String) -> String? {
        guard message.hasPrefix(LogLine.startedPrefix), message.hasSuffix(LogLine.startedSuffix),
              message.count > LogLine.startedPrefix.count + LogLine.startedSuffix.count
        else { return nil }
        return String(message.dropFirst(LogLine.startedPrefix.count).dropLast(LogLine.startedSuffix.count))
    }

    /// Exactly the `stampLength` characters `LogLine.stampFormat` spells.
    fileprivate static func isStamp(_ text: Substring) -> Bool {
        let stamp = Array(text)
        guard stamp.count == stampLength else { return false }
        return stamp.indices.allSatisfy { index in
            switch index {
            case 4, 7: return stamp[index] == "-"
            case 10: return stamp[index] == " "
            case 13, 16: return stamp[index] == ":"
            case 19: return stamp[index] == "."
            default: return stamp[index].isASCII && stamp[index].isNumber
            }
        }
    }
}
