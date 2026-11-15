import Foundation
import XCTest

/// The standing documents, named once.
///
/// Four checks each kept their own list of the documents and two their own
/// reader of a document's headings, and the copies differed (one counted a
/// `# comment` inside a fenced block as a section, one did not). This is the
/// one place that says which documents stand and what their headings are.
public enum StandingDocuments {

    /// The core documents that live in the repository, and nothing else.
    ///
    /// The rules document is the fourth of the standard and is not here: it left
    /// the repository (it is the owner's private `CLAUDE.local.md`, a link to
    /// Core), so `requireRules()` finds it. The crew's briefs are not here either: they
    /// live in a sibling repository behind the `.claude/agents` link, a symlink
    /// rather than a repo-relative path.
    private static let core = ["ARCHITECTURE.md", "README.md", "CHANGELOG.md"]

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

    /// The places the rules document may be, in the order they are tried, with no
    /// path of anybody's home written down (the repository is public).
    ///
    /// `CLAUDE.local.md` beside `Package.swift`; and, when this checkout is a
    /// linked worktree, the same name in the main checkout. A worktree's `.git` is
    /// a file reading `gitdir: <main>/.git/worktrees/<name>`; that directory's
    /// `commondir` (relative to it) names `<main>/.git`, whose parent is the main
    /// checkout. A fresh clone has a `.git` directory, so only the first is tried.
    public static func rulesCandidates() -> [URL] {
        let name = "CLAUDE.local.md"
        var found = [RepoSource.root.appendingPathComponent(name)]
        let dotGit = RepoSource.root.appendingPathComponent(".git")
        if let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
           pointer.hasPrefix("gitdir:") {
            let gitdir = URL(fileURLWithPath: String(pointer.dropFirst("gitdir:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines))
            if let common = try? String(contentsOf: gitdir.appendingPathComponent("commondir"),
                                        encoding: .utf8) {
                let mainGit = URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines),
                                  relativeTo: gitdir).standardizedFileURL
                found.append(mainGit.deletingLastPathComponent().appendingPathComponent(name))
            }
        }
        return found
    }

    /// The rules document's text. **The one place a check learns the rules are
    /// absent**: it throws `XCTSkip` (reason `rulesAbsent`) when no candidate
    /// exists, and nothing else does, so a check's CLAUDE half has no condition
    /// of its own to get wrong. A file that is there and cannot be read throws a
    /// plain failure, and an empty one comes back empty: both stay red.
    public static func requireRules(candidates: [URL] = rulesCandidates()) throws -> String {
        guard let url = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip(rulesAbsent(candidates))
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw RepoSource.Failure("\(url.path) could not be read: \(error)")
        }
    }

    /// Why a check skips its rules half: the paths sought.
    public static func rulesAbsent(_ candidates: [URL]) -> String {
        "the rules document is not at " + candidates.map(\.path).joined(separator: " or ")
            + " (a clone of the public repository does not carry the owner's private rules)"
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
    /// section sign: `ARCHITECTURE` (the hub and every page it links) or `CLAUDE`,
    /// which skips (`requireRules()`) when the rules are absent, so an empty list
    /// is never read as "the rules have no headings".
    public static func headings(of document: String) throws -> [String] {
        switch document {
        case "ARCHITECTURE":
            let hub = try RepoSource.text(of: "ARCHITECTURE.md")
            return try (headings(in: hub)
                + linkedPages(in: hub).flatMap { headings(in: try RepoSource.text(of: $0)) })
                .sorted { $0.count > $1.count }
        case "CLAUDE":
            return headings(in: try requireRules())
        default:
            throw RepoSource.Failure("\(document) is not a document whose headings pointers name")
        }
    }
}
