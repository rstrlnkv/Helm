import Foundation

/// Splitting a text file into lines **without throwing the endings away.**
///
/// Every file this module edits is somebody else's — `/etc/hosts`,
/// `~/.ssh/config`, `~/.ssh/known_hosts` — and each is read, changed in one
/// place and written back whole. `components(separatedBy:)` returns bodies
/// only, so a file that arrived with CRLF endings comes back as LF and every
/// line in it reads as changed by an app that was asked to edit one.
///
/// **CRLF is one `Character` in Swift** — a grapheme cluster — so it is matched
/// as itself. A reader that looks for `"\r"` and peeks ahead for `"\n"` matches
/// neither half; a reader that splits on `"\n"` alone matches nothing at all
/// and swallows the whole file as a single line, which is how forgetting one
/// trusted host emptied a `known_hosts`.
///
/// The three parsers each had their own copy of this before the third one was
/// written without it.
enum LineEndings {

    /// One entry per line: what the line said, and how it ended.
    ///
    /// A file whose last line has no ending is a file that must not gain one,
    /// so that line's `ending` is empty; the empty tail after a final newline
    /// is not a line at all and is not returned.
    static func split(_ text: String) -> [(body: String, ending: String)] {
        var out: [(body: String, ending: String)] = []
        var body = ""
        for character in text {
            if character == "\r\n" || character == "\n" || character == "\r" {
                out.append((body, String(character)))
                body = ""
            } else {
                body.append(character)
            }
        }
        if !body.isEmpty { out.append((body, "")) }
        return out
    }
}
