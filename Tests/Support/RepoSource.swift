import Foundation

/// The repository, as the tests that read it see it.
///
/// A whole family of checks in this suite reads source rather than calling it,
/// because what they pin is not something a type system says: a string
/// that must not be a literal, a list that must agree with the tree, a card
/// that must not spell a constant its own arithmetic reads. Every one of them
/// began with the same four lines —
///
/// ```swift
/// URL(fileURLWithPath: #filePath)
///     .deletingLastPathComponent()   // HelmUITests
///     .deletingLastPathComponent()   // Tests
///     .deletingLastPathComponent()   // repo
/// ```
///
/// — and the count of `deletingLastPathComponent`s is a fact about where the
/// test file sits, so a test under `Tests/Modules/<X>/UITests` needs a fourth
/// and a moved file needs an edit that nothing reports. **This walks up to
/// `Package.swift` instead**, which is the same answer from any depth and stops
/// being a number anybody has to keep right.
///
/// This does not go back and convert the twenty-odd files that already spell it
/// out; it is here so the next one does not make it twenty-one.
public enum RepoSource {

    /// The directory holding `Package.swift`, found by walking up from this
    /// file — which is in the repository by construction.
    ///
    /// A wrong answer is not silent: every reader below throws when the file it
    /// was asked for is not there, and the tests that use them assert what they
    /// read before asserting anything about it.
    public static let root: URL = {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath:
                url.appendingPathComponent("Package.swift").path) { return url }
            url = url.deletingLastPathComponent()
        }
        return url
    }()

    /// A file of the repository, by its path from the root.
    ///
    /// Wrapped rather than left to throw whatever `String(contentsOf:)` throws
    /// on its own: a file that is not valid UTF-8 comes back as Cocoa error
    /// 259 with no path in it at all, so a scan over many files could not say
    /// which one it had choked on.
    public static func text(of relative: String) throws -> String {
        do {
            return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        } catch {
            throw RepoSource.Failure("\(relative) could not be read: \(error)")
        }
    }

    /// The project's agent rules, `CLAUDE.local.md`, or nil when none is reachable.
    ///
    /// The rules live outside the tree and the code folder holds a gitignored
    /// symlink to them, so a checkout has the file, a linked worktree does not
    /// (it is found in the main checkout, whose root is the parent of the
    /// worktree's common git directory — read from the `.git` file's `gitdir`
    /// and its `commondir`, no process launched) and a fresh clone has neither.
    /// nil is that third state and nothing else: a file that exists and cannot
    /// be read throws, so it is never taken for an absent one. `from` is a seam
    /// for the test that proves the nil path; the default is this repository.
    public static func rules(from start: URL = root) throws -> String? {
        guard let found = rulesPaths(from: start).first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else { return nil }
        do {
            return try String(contentsOf: found, encoding: .utf8)
        } catch {
            throw RepoSource.Failure("CLAUDE.local.md could not be read: \(error)")
        }
    }

    /// The first place a `CLAUDE.local.md` entry of any kind exists (a file, or a
    /// symlink even a dangling one), judged without `rules(from:)`: whether a
    /// check may skip must not depend on the reader that could be broken. A nil
    /// from `rules(from:)` while this is non-nil is a failure naming this path.
    public static func rulesEntry(from start: URL = root) -> URL? {
        let fm = FileManager.default
        return rulesPaths(from: start).first {
            (try? fm.attributesOfItem(atPath: $0.path)) != nil
                || (try? fm.destinationOfSymbolicLink(atPath: $0.path)) != nil
        }
    }

    /// Where the rules may be: the root, then the main checkout's root, read from
    /// the `.git` file's `gitdir` and its `commondir` (no process launched).
    private static func rulesPaths(from start: URL) -> [URL] {
        var candidates = [start.appendingPathComponent("CLAUDE.local.md")]
        let dotGit = start.appendingPathComponent(".git")
        if let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
           pointer.hasPrefix("gitdir:") {
            let gitdir = URL(fileURLWithPath: String(pointer.dropFirst("gitdir:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: start)
            if let common = try? String(contentsOf: gitdir.appendingPathComponent("commondir"),
                                        encoding: .utf8) {
                let commonDir = URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines),
                                    relativeTo: gitdir).standardizedFileURL
                candidates.append(commonDir.deletingLastPathComponent()
                    .appendingPathComponent("CLAUDE.local.md"))
            }
        }
        return candidates
    }

    /// The same file, split — which is what a scan wants, since it reports the
    /// line it found something on.
    public static func lines(of relative: String) throws -> [String] {
        try text(of: relative).components(separatedBy: "\n")
    }

    /// Every `.swift` file under a directory of the repository, repo-relative
    /// and in walk order.
    ///
    /// One scan had this privately for the nine module UI directories, and the
    /// second scan that needed it — one that reads all of `Sources` — is the
    /// point at which it stops being one reader's business. The paths come back
    /// relative because that is what `text(of:)` and `lines(of:)` take, and
    /// because a finding has to name a file somebody can open.
    ///
    /// The enumerator carries its own error handler now: with none, Foundation
    /// drops a subdirectory it could not read and moves on without a word, so
    /// a mode-000 directory read as "empty" rather than "refused" — the same
    /// failure this file's own promise, "fails on a file it cannot read", is
    /// supposed to rule out.
    public static func swiftFiles(under relative: String) throws -> [String] {
        let base = root.appendingPathComponent(relative)
        var refusal: (any Error)?
        let walk = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: nil, options: [],
            errorHandler: { url, error in
                refusal = RepoSource.Failure("\(url.path) could not be enumerated: \(error)")
                return false
            })
        guard let walk else { return [] }
        var out: [String] = []
        while let url = walk.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            out.append(relative + url.path.replacingOccurrences(of: base.path, with: ""))
        }
        if let refusal { throw refusal }
        return out
    }

    /// A line with its comment tail removed.
    ///
    /// Every one of these scans has to do this, and for the same reason each
    /// time: the rule is explained in a comment somewhere, usually by quoting
    /// the very thing it forbids, so a scan that reads comments reports the
    /// explanation as the offence.
    public static func code(_ line: String) -> String {
        guard let range = line.range(of: "//") else { return line }
        return String(line[line.startIndex..<range.lowerBound])
    }

    /// A read or a parse that could not finish, naming the path it stopped at.
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
