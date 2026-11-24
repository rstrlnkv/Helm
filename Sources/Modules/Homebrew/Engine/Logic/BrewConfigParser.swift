import Foundation

/// Parses `brew config`'s answer, printed entirely to standard **output**
/// (`HomebrewEngine.config` says why `run`), into its `key: value` lines.
///
/// The document has no headings; Homebrew adds keys between releases.
/// `sections` below is where the three headings come from, Helm's reading
/// rather than Homebrew's words.
enum BrewConfigParser {

    /// nil for empty input, and for output in which no line is a `key: value`:
    /// `brew config` always prints such lines, so either is a refused query or
    /// an unreadable shape, never «this Mac has no configuration».
    ///
    /// Deliberately no `[]` answer, unlike `DoctorParser`, where a clean Mac
    /// really does print no findings. `brew config` has no such state.
    static func parse(_ text: String) -> [ConfigLine]? {
        guard !text.isEmpty else { return nil }
        var lines: [ConfigLine] = []
        for line in text.components(separatedBy: "\n") {
            // **The first colon, and the colon itself rather than `": "`.**
            // Values carry colons of their own (`ORIGIN` is a URL), so a scan
            // for the *last* colon hands back half the URL. Against `": "` the
            // first and last scans agree on every real line, so the rule is
            // tested only against the bare colon.
            //
            // A line with no colon is passed over: a document cut off by a
            // deadline ends in one, and half a key is worse than no line.
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon])
            guard !key.isEmpty else { continue }
            var value = Substring(line[line.index(after: colon)...])
            // One space, not a trim: the space is the format's, and a trim
            // would eat whitespace a value meant to carry.
            if value.first == " " { value = value.dropFirst() }
            lines.append(ConfigLine(key: key, value: String(value),
                                    section: section(of: key)))
        }
        return lines.isEmpty ? nil : lines
    }

    /// The heading a key is drawn under — **`.brew` for a key this table does
    /// not know.**
    ///
    /// Not a drop: Homebrew adds keys between releases, and a value nobody sees
    /// is worse than one under an imperfect heading. `.brew` is the group
    /// `brew config` is mostly about.
    static func section(of key: String) -> ConfigSection { sections[key] ?? .brew }

    /// Key to heading, hand-written, **beside the parser that reads it**.
    static let sections: [String: ConfigSection] = [
        // Homebrew's own installation and its checkout.
        "HOMEBREW_VERSION": .brew,
        "ORIGIN": .brew,
        "HEAD": .brew,
        "Last commit": .brew,
        "Branch": .brew,
        "Core tap": .brew,
        "Core cask tap": .brew,
        "HOMEBREW_PREFIX": .brew,
        "Homebrew Ruby": .brew,
        // The Mac underneath it.
        "CPU": .machine,
        "macOS": .machine,
        "Rosetta 2": .machine,
        // What it builds and downloads with. `Metal Toolchain` is a toolchain
        // brew may compile through, like `Clang`, not a fact about the hardware.
        "Clang": .tools,
        "Git": .tools,
        "Curl": .tools,
        "CLT": .tools,
        "Xcode": .tools,
        "Metal Toolchain": .tools,
    ]
}
