import Foundation

/// A pattern plus a file's facts, out comes a new name — or nothing, when the
/// pattern would produce something the filesystem should not be asked to take.
///
/// Returning nil rather than a best effort is the point. A rename that silently
/// becomes a move (`sub/{name}`), a file that loses its identity (an empty
/// pattern) or one that disappears from Finder (a leading dot) are all a rule
/// doing something nobody asked for, forever, once a folder is watched.
enum RenamePattern {

    /// `{name}` the file's name without its extension, `{date}` the date it was
    /// added as `2026-07-15`, `{counter}` a three-digit sequence number.

    /// The only token whose value comes from the file's name, and therefore the
    /// only reason applying a pattern twice can produce two different names.
    static let nameToken = "{name}"

    static func apply(_ pattern: String, to facts: FileFacts,
                      counter: Int = 1) -> String? {
        // Everything but the file's own name, substituted once: what is left is
        // both the template for this run and the shape of every name this
        // pattern has produced for this file before.
        let resolved = pattern
            .replacingOccurrences(of: "{date}", with: Self.day.string(from: facts.added))
            .replacingOccurrences(of: "{counter}", with: String(format: "%03d", counter))
        let stem = (facts.name as NSString).deletingPathExtension
        var name = resolved.replacingOccurrences(of: nameToken, with: stem)
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { return nil }
        // `/` is a path separator and `:` is one to the Finder; either turns a
        // rename into a move. A leading dot hides the file.
        guard !name.contains("/"), !name.contains(":"), !name.hasPrefix(".") else { return nil }

        // A rename that has already been applied must not apply again, and a
        // file the pattern already describes is one it has been applied to.
        // Renaming is the one action here that is not idempotent, so this is
        // what makes it safe to run unstamped — `RuleRunner` tolerates a stamp
        // that will not stick, and its own `target.path != url.path` is this
        // same test for the single pattern `{name}`. Every other shape walked
        // past it: the second sweep feeds the first sweep's output back into
        // `{name}` and gets something longer, once an hour, forever.
        guard !RenameShape(resolved: resolved).matches(stem) else { return facts.name }

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
enum SortBucket {

    static func name(for facts: FileFacts, scheme: SortScheme) -> String {
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
