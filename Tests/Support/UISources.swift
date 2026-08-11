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

    /// The nine module names, read out of `Package.swift`.
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

    /// Every capture of `patterns` in `files`, with comments stripped first.
    ///
    /// The comment strip is `RepoSource.code`'s and it is not optional: every
    /// rule in this repository is explained in a comment that quotes the very
    /// thing it forbids, so a scan that reads comments reports the explanation
    /// as the offence.
    public static func hits(matching patterns: [String], in files: [String]) throws -> [Hit] {
        let compiled = try patterns.map { try NSRegularExpression(pattern: $0) }
        var out: [Hit] = []
        for file in files {
            for (index, raw) in try RepoSource.lines(of: file).enumerated() {
                let code = RepoSource.code(raw)
                let range = NSRange(code.startIndex..., in: code)
                for pattern in compiled {
                    for match in pattern.matches(in: code, range: range) {
                        guard let captured = Range(match.range(at: 1), in: code),
                              let value = Double(code[captured]) else { continue }
                        out.append(Hit(file: file, line: index + 1, value: value,
                                       text: code.trimmingCharacters(in: .whitespaces)))
                    }
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
