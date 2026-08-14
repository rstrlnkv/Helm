import Foundation

/// Reading the log back — **the one place in this app a log line is parsed.**
///
/// CLAUDE.md's rule is that the tail is filled from the same parts the file line
/// is spelled from, never by parsing the line back apart, and that rule stands
/// for `write`: the live path holds the parts and hands them over. A *seed* has
/// no parts to hold. The file is all there is, so it parses — here, once, in a
/// type whose name says so — and `LogSeed`'s obligation in exchange is to be the
/// exact inverse of `LogLine.format` rather than an approximate reader of it.
/// `ThePageShowsTheLogAndNotTheSessionTests` holds the round trip.
///
/// **A line it cannot read is kept whole and claims nothing.** Dropping it would
/// hide the half-written line a crash left behind — which is the line somebody
/// opened the page for — and guessing at its parts would put a level and a module
/// on text the app did not write. So the whole line becomes the message, the
/// category is empty, the level is `info`, and the date is the one on the line
/// above it: adjacent in the file, adjacent on the page. Nothing else is claimed.
///
/// **On redaction.** `Redact` runs at the call site, before `write`, so the file
/// never held a VPN name or a home path and a parse cannot bring one back: a
/// seeded line carries exactly what «Show in Finder» would show. What a parse
/// *can* be wrong about is the clock — the file spells local time and no offset,
/// so lines written in another time zone are drawn at the wall-clock time they
/// were written at rather than the instant. The alternative is discarding them.
enum LogSeed {

    /// What one line of the file turned back into.
    enum Line: Equatable {
        case entry(LogEntry)
        /// Not a line this app wrote, or not all of one.
        case unreadable(String)
    }

    /// The stamp `LogLine.format` writes, read the other way — and read once a
    /// minute rather than once a line.
    ///
    /// **Measured 2026-08-14**, three readings in a `-O` binary on this Mac:
    /// `DateFormatter.date(from:)` costs 48.8, 52.1 and 77.8 µs, so a thousand
    /// lines parsed the plain way is 49–78 ms — spent on the main thread the
    /// first time somebody opens the page. A thousand lines of the owner's log
    /// span about 460 seconds, so the same thousand stamps hold eight minutes:
    /// eight of those calls instead of a thousand, measured at 1 ms for the lot.
    /// Remembering the *second* instead would have left 460 of them, which is
    /// why the minute is what is remembered and the seconds and milliseconds
    /// after it are arithmetic on the result.
    ///
    /// A minute rather than a day because a zone offset can change inside a day
    /// and cannot change inside a minute — the arithmetic is only safe under a
    /// constant offset, and that is the largest unit that guarantees one.
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
            guard stamp.count == 23,
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
    /// line — building a `DateFormatter` is 77–100 µs (three readings, 2026-08-14),
    /// which over the thousand lines of a seed is more than the parse the minute
    /// cache above exists to save.
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

    /// The site `LogLine.format` puts last, and only when the tail really has its
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
    ///   - fallback: the date for an unreadable line with no readable line above
    ///     it — the file's own modification date, never now.
    ///   - limit: how many lines are wanted, dropped **before** the parse rather
    ///     than after it. The byte window below holds about 3 400 lines of a log
    ///     whose newest thousand average 76 bytes, and the tail keeps 1 000, so
    ///     parsing the window and then trimming is two thirds of the work thrown
    ///     away.
    static func entries(from text: String, startedMidFile: Bool, dated fallback: Date,
                        keepingLast limit: Int = .max,
                        using formatter: Stamps) -> [LogEntry] {
        var lines = text.components(separatedBy: "\n")
        if startedMidFile, !lines.isEmpty { lines.removeFirst() }
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        var out: [LogEntry] = []
        var last = fallback
        for line in lines where !line.isEmpty {
            switch parse(line, using: formatter) {
            case .entry(let entry):
                last = entry.date
                out.append(entry)
            case .unreadable(let text):
                out.append(LogEntry(date: last, level: .info, category: "", message: text))
            }
        }
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
    /// Bounded by bytes as well as by lines: the file is 2 MB before it rolls
    /// over, and reading all of it to keep the last thousand lines is the whole
    /// volume in memory for a page somebody opened to read the end of it. A read
    /// that starts at an offset says so, so the fragment it lands in the middle of
    /// is dropped rather than drawn.
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
                guard let data = try? handle.readToEnd(),
                      let text = String(data: data, encoding: .utf8)
                else { return }
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
