import Foundation

/// A pattern plus a file's facts, out comes a new name — or nothing, when the
/// pattern would produce something the filesystem should not be asked to take.
///
/// Returning nil rather than a best effort is the point. A rename that silently
/// becomes a move (`sub/{name}`), a file that loses its identity (an empty
/// pattern) or one that disappears from Finder (a leading dot) are all a rule
/// doing something nobody asked for, forever, once a folder is watched.
public enum RenamePattern {

    /// `{name}` the file's name without its extension, `{date}` the date it was
    /// added as `2026-07-15`, `{counter}` a three-digit sequence number.
    public static let tokens = ["{name}", "{date}", "{counter}"]

    public static func apply(_ pattern: String, to facts: FileFacts,
                             counter: Int = 1) -> String? {
        let stem = (facts.name as NSString).deletingPathExtension
        var name = pattern
            .replacingOccurrences(of: "{name}", with: stem)
            .replacingOccurrences(of: "{date}", with: Self.day.string(from: facts.added))
            .replacingOccurrences(of: "{counter}", with: String(format: "%03d", counter))
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { return nil }
        // `/` is a path separator and `:` is one to the Finder; either turns a
        // rename into a move. A leading dot hides the file.
        guard !name.contains("/"), !name.contains(":"), !name.hasPrefix(".") else { return nil }

        // The extension is the file's own, never the pattern's: a rule that
        // renames a PDF must not be able to make it something else in passing.
        let ext = (facts.name as NSString).pathExtension
        return ext.isEmpty ? name : name + "." + ext
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// The subfolder a sorting rule puts a file in.
public enum SortBucket {

    public static func name(for facts: FileFacts, scheme: SortScheme) -> String {
        switch scheme {
        case .kind: kindName(facts.kind)
        case .month: month.string(from: facts.added)
        }
    }

    /// English and fixed, like the month. These are folder names on disk: they
    /// outlive the language the app happened to be in when the rule ran, and a
    /// folder that renames itself when someone switches language is a folder
    /// that has lost its contents as far as every other rule is concerned.
    private static func kindName(_ kind: FileKind) -> String {
        switch kind {
        case .image: "Images"
        case .document: "Documents"
        case .archive: "Archives"
        case .video: "Video"
        case .audio: "Audio"
        case .folder: "Folders"
        case .other: "Other"
        }
    }

    /// `2026-07` — sorts by name into chronological order, which a localised
    /// month name does not. The date *added*, because "when this arrived" is
    /// what a Downloads folder is asking about.
    private static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}
