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

    /// The names to delete, oldest first. Anything that is not one of ours is
    /// never named — a person's own file in that folder is theirs.
    public static func pruned(_ names: [String], keeping limit: Int) -> [String] {
        let ours = names.filter(isOurs).sorted()
        guard ours.count > limit else { return [] }
        return Array(ours.prefix(ours.count - limit))
    }
}
