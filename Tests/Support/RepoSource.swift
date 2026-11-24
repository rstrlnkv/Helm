import Foundation

/// The repository, as the tests that read it see it.
///
/// A family of checks reads source rather than calling it, because what they
/// pin is not something a type system says: a string that must not be a
/// literal, a list that must agree with the tree.
///
/// The root is found by walking up to `Package.swift`, the same answer from any
/// depth, rather than by a count of `deletingLastPathComponent()` calls that is
/// a fact about where the test file sits.
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
    /// Read from the tree rather than from a build product: a scan asserts
    /// about what is written, and a stale module would answer for the wrong source.
    ///
    /// Wrapped because a file that is not valid UTF-8 throws Cocoa error 259
    /// with no path in it, and a scan over many files must say which one.
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
    /// Relative, because that is what `text(of:)` and `lines(of:)` take and
    /// what a finding names.
    ///
    /// The enumerator carries an error handler: with none, Foundation drops a
    /// subdirectory it could not read without a word, so a refused directory
    /// would read as empty.
    public static func swiftFiles(under relative: String) throws -> [String] {
        let base = root.appendingPathComponent(relative)
        var refusal: (any Error)?
        let walk = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: nil, options: [],
            errorHandler: { url, error in
                refusal = RepoSource.Failure("\(url.path) could not be enumerated: \(error)")
                return false
            })
        guard let walk else { throw RepoSource.Failure("\(base.path) could not be enumerated") }
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
    /// A rule is usually explained in a comment that quotes what it forbids,
    /// so a scan that read comments would report the explanation.
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
