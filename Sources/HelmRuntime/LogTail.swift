import Foundation

/// One line of the log, before it becomes a line.
///
/// The file gets a formatted string; a reader wants the parts back, so the tail
/// keeps them apart rather than parsing them out again. `LogLine.format` remains
/// the one place a line is spelled — this is what it is spelled *from*.
public struct LogEntry: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let date: Date
    public let level: LogLevel
    public let category: String
    public let message: String

    public init(date: Date, level: LogLevel, category: String, message: String) {
        self.date = date
        self.level = level
        self.category = category
        self.message = message
    }

    public static func == (a: LogEntry, b: LogEntry) -> Bool {
        a.date == b.date && a.level == b.level && a.category == b.category && a.message == b.message
    }
}

/// The last N lines, kept in memory so a dev build can watch them arrive.
///
/// Bounded on purpose: a window for finding memory bugs must not be one. The
/// oldest line goes when the newest arrives, which is the behaviour of every
/// `tail -f` anybody has ever read.
struct LogTail: Sendable {
    let limit: Int
    private var buffer: [LogEntry] = []

    init(limit: Int = 1000) {
        self.limit = limit
        buffer.reserveCapacity(limit)
    }

    var entries: [LogEntry] { buffer }

    mutating func append(_ entry: LogEntry) {
        buffer.append(entry)
        if buffer.count > limit { buffer.removeFirst(buffer.count - limit) }
    }

    mutating func clear() { buffer.removeAll(keepingCapacity: true) }
}

/// What the reader chose to see.
///
/// Two questions, ANDed, because they are the two a person actually asks: *what
/// went wrong* (level) and *what is this module doing* (category). Order of
/// arrival is never touched — a log that reorders itself is unreadable.
public enum LogFilter {

    public static func apply(_ entries: [LogEntry],
                             minimumLevel: LogLevel,
                             categories: Set<String>) -> [LogEntry] {
        entries.filter { entry in
            guard entry.level.rank >= minimumLevel.rank else { return false }
            return categories.isEmpty || categories.contains(entry.category)
        }
    }

    /// The modules that have actually said something, sorted so the menu does
    /// not reshuffle as lines arrive.
    public static func categories(in entries: [LogEntry]) -> [String] {
        Array(Set(entries.map(\.category))).sorted()
    }
}

extension LogLevel {
    /// Ordered so a minimum level is a comparison rather than a switch at every
    /// call site.
    var rank: Int {
        switch self {
        case .info: return 0
        case .warn: return 1
        case .error: return 2
        }
    }
}
