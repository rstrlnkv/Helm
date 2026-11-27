import Darwin
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

    /// Read the first local `AGENTS.md`, following a recognized project entry.
    /// Managed entries use sibling Core unless given a trusted `coreDirectory`
    /// or, for the default checkout, an absolute `CORE_DIR` from the environment.
    /// Return nil if both checkouts lack the file; throw for bad entries or reads.
    public static func rules(from start: URL? = nil, coreDirectory: URL? = nil) throws -> String? {
        let core = start == nil ? ProcessInfo.processInfo.environment["CORE_DIR"] : nil
        let configuredCore = coreDirectory ?? core.flatMap { path in
            path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true) : nil
        }
        for entry in rulesPaths(from: start ?? root) {
            do {
                // Unlike fileExists, this sees a dangling symlink as an entry.
                _ = try FileManager.default.attributesOfItem(atPath: entry.path)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                && error.code == CocoaError.fileReadNoSuchFile.rawValue {
                continue
            } catch {
                throw Failure("\(entry.path) could not be inspected: \(error)")
            }
            let text = try readRules(at: entry)
            guard let target = try projectRulesPath(in: text, entry: entry, coreDirectory: configuredCore)
            else { return text }
            return try readRules(at: target)
        }
        return nil
    }

    private static func readRules(at file: URL) throws -> String {
        do {
            guard try file.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else { throw Failure("not a regular file") }
            return try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw Failure("\(file.path) could not be read: \(error)")
        }
    }

    private static func projectRulesPath(in text: String, entry: URL, coreDirectory: URL?) throws -> URL? {
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.first == "# Local agent entry point" else { return nil }
        let malformed = Failure("\(entry.path): malformed local agent entry point")
        guard !lines.contains(where: {
            let line = $0.drop(while: \.isWhitespace)
            return line.hasPrefix("```") || line.hasPrefix("~~~")
        }) else { throw malformed }

        let bullets = lines.filter { $0.hasPrefix("- ") }
        let siblingCore = entry.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Core", isDirectory: true)
        let core: URL, name: String, supplied: Substring?
        if bullets == ["- `../Core/AGENTS.md`", "- `../Core/helm/AGENTS.md`"] {
            (core, name, supplied) = (siblingCore, "AGENTS.md", nil)
        } else {
            // The managed Core row is not a source of paths to read.
            let managedPrefix = "- Project: "
            guard bullets.count == 1 || (bullets.count == 2 && bullets[0].hasPrefix("- Core (if present): ")),
                  let row = bullets.last, row.hasPrefix(managedPrefix) else { throw malformed }
            let path = row.dropFirst(managedPrefix.count)
            guard path.hasPrefix("/"), !path.contains("\0"),
                  path.hasSuffix("/AGENTS.md") || path.hasSuffix("/CLAUDE.md") else { throw malformed }
            (core, name, supplied) = (coreDirectory ?? siblingCore,
                                      path.hasSuffix("/AGENTS.md") ? "AGENTS.md" : "CLAUDE.md", path)
        }

        let canonicalCore = try resolvedRulesPath(core)
        let project = canonicalCore.appendingPathComponent("helm", isDirectory: true)
        let target = project.appendingPathComponent(name, isDirectory: false)
        let outOfScope = Failure("\(entry.path): project target is outside \(project.path)")
        // Compare trusted spellings, including Foundation's spelling without /private, before opening the target.
        if let supplied, supplied != target.path {
            let spellings = [core, canonicalCore.resolvingSymlinksInPath()]
            guard spellings.contains(where: {
                supplied == $0.appendingPathComponent("helm/\(name)", isDirectory: false).path
            }) else { throw outOfScope }
        }
        let resolved = try resolvedRulesPath(target)
        guard resolved.path.hasPrefix(project.path + "/") else { throw outOfScope }
        return resolved
    }

    private static func resolvedRulesPath(_ file: URL) throws -> URL {
        // Foundation may return the input unchanged if symlink resolution fails.
        guard let resolved = realpath(file.path, nil) else {
            throw Failure("\(file.path) could not be resolved")
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: false)
    }

    /// Where the rules may be: the root, then the main checkout's root, read from
    /// the `.git` file's `gitdir` and its `commondir` (no process launched).
    private static func rulesPaths(from start: URL) -> [URL] {
        var candidates = [start.appendingPathComponent("AGENTS.md")]
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
                    .appendingPathComponent("AGENTS.md"))
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
