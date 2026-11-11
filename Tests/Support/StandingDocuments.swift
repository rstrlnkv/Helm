import Foundation
import XCTest

/// The standing documents, named once.
///
/// Four checks each kept their own list of the documents and two their own
/// reader of a document's headings, and the copies differed (one counted a
/// `# comment` inside a fenced block as a section, one did not). This is the
/// one place that says which documents stand and what their headings are.
public enum StandingDocuments {

    /// The documents of the standard that are in the tree, and nothing else.
    ///
    /// The agent rules are not here: they live outside the tree, behind the
    /// gitignored `CLAUDE.local.md` link, and `rules()` reads them.
    private static let core = ["ARCHITECTURE.md", "README.md", "CHANGELOG.md"]

    /// The agent rules, or a skip saying why they are not there. A fresh clone
    /// or CI has no `CLAUDE.local.md`; that is the state of the machine, not a
    /// finding, and only the checks about the rules file ask for it.
    public static func rules(from start: URL = RepoSource.root) throws -> String {
        guard let text = try RepoSource.rules(from: start) else {
            if let entry = RepoSource.rulesEntry(from: start) {
                throw RepoSource.Failure("\(entry.path) exists but the rules reader returned nothing for it")
            }
            throw XCTSkip("no CLAUDE.local.md in this checkout or the main one — the agent rules are not in the tree")
        }
        return text
    }

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
    /// section sign: `ARCHITECTURE` (the hub and every page it links) or `CLAUDE` (the rules file; a skip when it is not reachable).
    public static func headings(of document: String) throws -> [String] {
        switch document {
        case "ARCHITECTURE":
            let hub = try RepoSource.text(of: "ARCHITECTURE.md")
            return try (headings(in: hub)
                + linkedPages(in: hub).flatMap { headings(in: try RepoSource.text(of: $0)) })
                .sorted { $0.count > $1.count }
        case "CLAUDE":
            return headings(in: try rules())
        default:
            throw RepoSource.Failure("\(document) is not a document whose headings pointers name")
        }
    }
}
