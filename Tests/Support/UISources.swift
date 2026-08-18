import Foundation

/// The Swift a module page is drawn from: the design system plus the UI half of
/// every module.
///
/// Two of the four v3 ladders are read off the source rather than off the
/// render, and this is the enumeration both of them share — the reason
/// `RepoSource` exists one level down, one level up.
///
/// **Why the source and not the rendered tree, for space and for type.** The
/// layer tree an `NSHostingView` produces is flat and it is not annotated: a
/// padding leaves no layer at all, and a `Text` arrives as a bitmap with no font
/// on it. Radius survives (`CALayer.cornerRadius`) and geometry survives
/// (frames), and those two ladders are measured on the render, in
/// `RadiusLadderRatchetTests` and `LongStringGeometryRatchetTests`. The other
/// two cannot be, by anything short of pixel archaeology — so they are read off
/// the lines that produce them, which is also the only form in which a finding
/// can name a file and a line for the commit that lowers the number.
///
/// The precedent for reading source in this suite is `KeyboardReachableControlsTests`,
/// and the reason is the same one it gives: the defect is invisible at runtime.
public enum UISources {

    /// One off-ladder value, where it was written.
    public struct Hit: Sendable, Equatable {
        public let file: String
        public let line: Int
        public let value: Double
        public let text: String

        public init(file: String, line: Int, value: Double, text: String) {
            self.file = file
            self.line = line
            self.value = value
            self.text = text
        }

        public var where_: String { "\(file):\(line)" }
    }

    /// Every module's name, read out of `Package.swift`.
    ///
    /// Not a list written here. A hand-written list of modules is tied to the
    /// thing it names or it is a comment (CLAUDE.md), and the manifest is where
    /// the tree says which modules exist — so a module added to the package
    /// arrives in these scans without anybody remembering to add it, and a
    /// module renamed makes the scan throw rather than quietly cover eight.
    public static func moduleNames() throws -> [String] {
        let manifest = try RepoSource.text(of: "Package.swift")
        let pattern = try NSRegularExpression(pattern: #"Module\(name:\s*"([A-Za-z]+)""#)
        let range = NSRange(manifest.startIndex..., in: manifest)
        return pattern.matches(in: manifest, range: range).compactMap {
            Range($0.range(at: 1), in: manifest).map { String(manifest[$0]) }
        }
    }

    /// Every `.swift` file a module page can be drawn from, repo-relative.
    public static func files() throws -> [String] {
        var out = try RepoSource.swiftFiles(under: "Sources/HelmUI")
        for module in try moduleNames() {
            let directory = "Sources/Modules/\(module)/UI"
            let found = try RepoSource.swiftFiles(under: directory)
            guard !found.isEmpty else {
                throw Failure("\(directory) holds no Swift — the scan is not reading \(module)")
            }
            out += found
        }
        return out.sorted()
    }

    /// The same, plus the app shell — every file that draws a *window*.
    ///
    /// Wider than `files()` on purpose, and only one scan wants it. Space and
    /// type numbers are read off the module pages because that is the surface
    /// the mockups were audited against; a **font style** is a word of the
    /// vocabulary rather than a measurement of a page, and `AboutPage`,
    /// `LogView` and `SettingsWindow` say it as loudly as any module does. A
    /// sweep that converted them with nothing counting them would leave the
    /// eighty-sixth site free to arrive in the one target nobody was reading.
    public static func everyDrawnFile() throws -> [String] {
        (try files() + RepoSource.swiftFiles(under: "Sources/HelmApp")).sorted()
    }

    /// One compiled pattern and the way it answers with a number.
    ///
    /// Two kinds of scan share this walk and differ only here: a ladder reads
    /// the value out of the match (`spacing: 15` → 15), and a vocabulary is
    /// handed the value from outside (`.font(.callout)` → 12, which is macOS's
    /// fact and not the line's). Everything else — the file list, the comment
    /// strip, the line number, the reported text — is the same scan, and was
    /// written twice before this type existed.
    private struct Rule {
        let expression: NSRegularExpression
        let value: (NSTextCheckingResult, String) -> Double?
    }

    /// Every capture of `patterns`, with comments stripped first.
    ///
    /// The comment strip is `RepoSource.code`'s and it is not optional: every
    /// rule in this repository is explained in a comment that quotes the very
    /// thing it forbids, so a scan that reads comments reports the explanation
    /// as the offence.
    public static func hits(matching patterns: [String], in files: [String]) throws -> [Hit] {
        try scan(try ladderRules(patterns), in: files)
    }

    /// The same patterns against a string, for a fixture.
    ///
    /// **The reason this is here and not in each test.** Both ratchets carry a
    /// fixture case whose comment says it goes «through exactly what the tree
    /// goes through», and both then re-implemented the walk beside it — so the
    /// sentence was a claim about two copies staying in step, which is the
    /// shape this repository keeps paying for. One walk now, and the claim is
    /// true by construction.
    public static func hits(matching patterns: [String], in source: String) throws -> [Hit] {
        scan(try ladderRules(patterns), lines: source.components(separatedBy: "\n"),
             of: "fixture")
    }

    /// Every line a pattern matches at all, with no number in it — a style
    /// rather than a size. The value is what macOS resolves that style to.
    public static func sites(matching patterns: [String: Double],
                             in files: [String]) throws -> [Hit] {
        try scan(try styleRules(patterns), in: files)
    }

    /// The same, against a string.
    public static func sites(matching patterns: [String: Double],
                             in source: String) throws -> [Hit] {
        scan(try styleRules(patterns), lines: source.components(separatedBy: "\n"),
             of: "fixture")
    }

    private static func ladderRules(_ patterns: [String]) throws -> [Rule] {
        try patterns.map { pattern in
            Rule(expression: try NSRegularExpression(pattern: pattern)) { match, code in
                Range(match.range(at: 1), in: code).flatMap { Double(code[$0]) }
            }
        }
    }

    private static func styleRules(_ patterns: [String: Double]) throws -> [Rule] {
        try patterns.map { pattern, size in
            Rule(expression: try NSRegularExpression(pattern: pattern)) { _, _ in size }
        }
    }

    private static func scan(_ rules: [Rule], in files: [String]) throws -> [Hit] {
        try files.flatMap { scan(rules, lines: try RepoSource.lines(of: $0), of: $0) }
    }

    private static func scan(_ rules: [Rule], lines: [String], of file: String) -> [Hit] {
        var out: [Hit] = []
        for (index, raw) in lines.enumerated() {
            let code = RepoSource.code(raw)
            let range = NSRange(code.startIndex..., in: code)
            for rule in rules {
                for match in rule.expression.matches(in: code, range: range) {
                    guard let value = rule.value(match, code) else { continue }
                    out.append(Hit(file: file, line: index + 1, value: value,
                                   text: code.trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        return out
    }

    /// A count that has been through the same regular expressions, so a scan
    /// that has quietly stopped matching anything is a failure rather than a
    /// zero. The ladders assert against this before they assert their own
    /// numbers.
    public static func offLadder(_ hits: [Hit], ladder: Set<Double>) -> [Hit] {
        hits.filter { !ladder.contains(abs($0.value)) }
    }

    /// Grouped for the failure message: which value, how often, and where it is
    /// worst — a bare number tells the next person nothing about where to start.
    public static func summary(_ hits: [Hit]) -> String {
        let byValue = Dictionary(grouping: hits, by: \.value)
            .sorted { $0.value.count > $1.value.count }
            .map { "\(trim($0.key)) pt ×\($0.value.count)" }
        let byFile = Dictionary(grouping: hits) { URL(fileURLWithPath: $0.file).lastPathComponent }
            .sorted { $0.value.count > $1.value.count }
            .prefix(6)
            .map { "\($0.key) ×\($0.value.count)" }
        // Five lines, spelled out. A count and a histogram say what to fix and
        // not where to start, and the commit that lowers this number has to
        // begin at a line.
        let lines = hits.sorted { ($0.file, $0.line) < ($1.file, $1.line) }.prefix(5)
            .map { "  \($0.where_)  \($0.text.prefix(90))" }
        return "values: " + byValue.joined(separator: ", ")
            + "\nworst files: " + byFile.joined(separator: ", ")
            + "\nfirst five:\n" + lines.joined(separator: "\n")
    }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
