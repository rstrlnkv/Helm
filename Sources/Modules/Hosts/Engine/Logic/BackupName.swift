import Foundation

/// What a saved copy of `/etc/hosts` is called, and which ones go.
///
/// The name sorts by time as plain text, so the directory listing is the
/// history and nothing has to parse a date back to order them.
public enum BackupName {

    public static let suffix = ".hosts"

    /// `2026-08-17T120000Z.hosts`. No colons — they are legal on APFS and a
    /// lifetime of trouble everywhere a path is typed.
    ///
    /// UTC, and every field zero-padded to a fixed width: both are what make
    /// the text order the time order. A local calendar would reorder an hour
    /// of names twice a year, and an unpadded month would sort `10` before `9`.
    public static func name(at date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d%02d%02dZ%@",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0, suffix)
    }

    /// Whether a name is one this module made — the one place that question is
    /// answered, for the listing, the pruning, the reading and the deleting.
    ///
    /// Two conditions, and the second is not decoration. A backup id reaches
    /// the engine inside a payload, so `../../etc/sudoers.hosts` is a string
    /// this app can be handed; `appendingPathComponent` would build it happily
    /// and leave the kernel to resolve the `..`. A name is a *name*, so it is
    /// its own last path component. `name(at:)` never produces anything else,
    /// so nothing legitimate is refused.
    public static func isOurs(_ name: String) -> Bool {
        name.hasSuffix(suffix) && (name as NSString).lastPathComponent == name
    }

    /// The moment a name was written for, or `nil` for anything that is not one
    /// of ours.
    ///
    /// **The name orders the history and this does not order anything** — the
    /// doc above still stands, nothing parses a date back to sort by it. This
    /// exists because a menu of copies has to say *when*, and the stamp is UTC:
    /// a page that cut the digits out of the name would be telling somebody in
    /// Vladivostok about a Greenwich afternoon. `HelmDates` writes it in the
    /// reader's zone and language once it is a `Date`.
    ///
    /// Read with a fixed-format formatter on `en_US_POSIX`, for the reason
    /// `HelmDates.storage` carries: any other locale answers to the reader's
    /// calendar, and a Japanese one reads this as an era year and returns nil.
    public static func date(of name: String) -> Date? {
        guard isOurs(name) else { return nil }
        return stamp.date(from: String(name.dropLast(suffix.count)))
    }

    /// Built once, and shared by nothing else: it is the inverse of the format
    /// string above, and the two belong side by side.
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss'Z'"
        // No `isLenient = false` here, and the line was written and then
        // measured out: it is the default, and setting it either way parses
        // «2026-13-45T999999Z» to nil just the same. A line whose comment
        // claims a guard it does not provide is worse than no line.
        return formatter
    }()

    /// The names to delete, oldest first. Anything that is not one of ours is
    /// never named — a person's own file in that folder is theirs.
    public static func pruned(_ names: [String], keeping limit: Int) -> [String] {
        let ours = names.filter(isOurs).sorted()
        guard ours.count > limit else { return [] }
        return Array(ours.prefix(ours.count - limit))
    }
}
