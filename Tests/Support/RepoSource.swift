import Foundation

/// The repository, as the tests that read it see it.
///
/// A whole family of checks in this suite reads source rather than calling it,
/// because what they pin is not something a type system says: an event name
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
    public static func text(of relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// The same file, split — which is what a scan wants, since it reports the
    /// line it found something on.
    public static func lines(of relative: String) throws -> [String] {
        try text(of: relative).components(separatedBy: "\n")
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
}
