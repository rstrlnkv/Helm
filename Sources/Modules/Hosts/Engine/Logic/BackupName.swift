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

    /// The names to delete, oldest first. Anything that is not one of ours is
    /// never named — a person's own file in that folder is theirs.
    public static func pruned(_ names: [String], keeping limit: Int) -> [String] {
        let ours = names.filter { $0.hasSuffix(suffix) }.sorted()
        guard ours.count > limit else { return [] }
        return Array(ours.prefix(ours.count - limit))
    }
}
