import Foundation

/// The standing documents, named once.
///
/// Four checks each kept their own list of the documents and two their own
/// reader of a document's headings, and the copies differed (one counted a
/// `# comment` inside a fenced block as a section, one did not). This is the
/// one place that says which documents stand and what their headings are.
public enum StandingDocuments {

    /// The four core documents of the standard, and nothing else.
    ///
    /// The crew's briefs are not here: they live in a sibling repository behind the
    /// `.claude/agents` link, a symlink rather than a repo-relative path.
    private static let core = ["ARCHITECTURE.md", "CLAUDE.md", "README.md", "CHANGELOG.md"]

    /// `core` and the pages `ARCHITECTURE.md` links.
    public static func all() -> [String] {
        core + ((try? RepoSource.text(of: "ARCHITECTURE.md")).map(linkedPages(in:)) ?? [])
    }

    /// The repo-relative pages a hub links, in link order — what the hub
    /// links, not what a directory happens to hold.
    public static func linkedPages(in hub: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\]\((Architecture/[A-Za-z0-9]+\.md)\)"#) else { return [] }
        let ns = hub as NSString
        return regex.matches(in: hub, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    /// The lines of a document with a flag for each: is it a heading outside
    /// fenced code. The one walker `headings(in:)` and `section(_:in:)` share.
    private static func walk(_ text: String) -> [(line: String, heading: String?)] {
        var inFence = false
        return text.components(separatedBy: "\n").map { line in
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle(); return (line, nil) }
            guard !inFence, line.hasPrefix("#") else { return (line, nil) }
            let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return (line, title.isEmpty ? nil : title)
        }
    }

    /// Heading texts of a document, outside fenced code, as written, longest
    /// first — so a short heading that is a prefix of a longer one never wins a
    /// match the longer one deserved.
    public static func headings(in text: String) -> [String] {
        walk(text).compactMap(\.heading).sorted { $0.count > $1.count }
    }

    /// The lines from the heading `heading` (exclusive) to the next heading of any
    /// level (exclusive), outside fenced code, or nil when the text has no such
    /// heading. A caller reads a section by its heading, not by the file it sits in.
    public static func section(_ heading: String, in text: String) -> [String]? {
        let lines = walk(text)
        guard let start = lines.firstIndex(where: { $0.heading == heading }) else { return nil }
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex(where: { $0.heading != nil }) ?? rest.endIndex
        return lines[(start + 1)..<end].map(\.line)
    }

    /// The headings of a document by the bare name a pointer writes before the
    /// section sign: `ARCHITECTURE` (the hub and every page it links) or `CLAUDE`.
    public static func headings(of document: String) throws -> [String] {
        switch document {
        case "ARCHITECTURE":
            let hub = try RepoSource.text(of: "ARCHITECTURE.md")
            return try (headings(in: hub)
                + linkedPages(in: hub).flatMap { headings(in: try RepoSource.text(of: $0)) })
                .sorted { $0.count > $1.count }
        case "CLAUDE":
            return headings(in: try RepoSource.text(of: "CLAUDE.md"))
        default:
            throw UISources.Failure("\(document) is not a document whose headings pointers name")
        }
    }
}
