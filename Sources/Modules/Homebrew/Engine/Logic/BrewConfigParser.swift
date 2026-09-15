import Foundation

/// Parses `brew config`'s answer — printed entirely to standard **output**, one
/// tool run through the ordinary `ProcessRunner.run` — into the `key: value`
/// lines it is made of.
///
/// **`run`, not `runCapturingDiagnostics`.** Measured on this Mac, Homebrew
/// 7.0.1, 2026-09-15: 555 bytes of stdout against 0 of stderr, exit 0. That is
/// the opposite of `brew doctor` (1 byte of stdout against 1,194 of stderr,
/// exit 1), so the runner `DoctorParser`'s query needs is the wrong one here —
/// it would merge a tap's deprecation warning into the document and this parser
/// would read the warning's own colon as a configuration key.
///
/// The document is eighteen lines of `key: value` on this Mac and has no
/// headings in it at all. `sections` below is where the three headings come
/// from, and they are Helm's reading rather than Homebrew's words.
enum BrewConfigParser {

    /// nil for empty input — the tool said nothing at all, which must not read
    /// as «this Mac has no configuration»: that reading is what a silently
    /// refused query would also produce. nil as well for real output in which
    /// no line is a `key: value` at all, for the same reason: `brew config`
    /// always prints such lines, so output made of nothing else is output this
    /// build did not understand rather than a Mac with nothing to say.
    ///
    /// There is deliberately no `[]` answer here, and that is the difference
    /// from `DoctorParser`: an empty array is honest there, because a clean Mac
    /// really does produce output with no findings in it. `brew config` has no
    /// such state.
    static func parse(_ text: String) -> [ConfigLine]? {
        guard !text.isEmpty else { return nil }
        var lines: [ConfigLine] = []
        for line in text.components(separatedBy: "\n") {
            // **The first colon, and the colon itself rather than `": "`.**
            //
            // Two decisions, and the second is what makes the first worth
            // anything. Three of the eighteen values on this Mac carry a colon
            // of their own — `ORIGIN` is a URL, and a URL's colon is followed
            // by `//` — so a scan for the *last* colon reads `ORIGIN: https`
            // as the key and hands back half the URL. Written against `": "`
            // the two scans cannot be told apart at all: no value on this
            // machine holds a colon **followed by a space**, so first and last
            // agree on every one of the eighteen lines and the rule is a rule
            // about nothing. Against the bare colon the difference is visible
            // on brew's own document, which is where it has to be visible.
            //
            // A line with no colon is not a `key: value` and is passed over:
            // brew's document cut off mid-line by a deadline ends in exactly
            // such a line, and half a key under a heading is worse than the
            // line not being there.
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon])
            guard !key.isEmpty else { continue }
            var value = Substring(line[line.index(after: colon)...])
            // One space, not a trim: brew writes `key: value`, and the space
            // after the colon is the format's rather than the value's. Trimming
            // whatever whitespace follows would also eat the indentation of a
            // value that meant to carry some.
            if value.first == " " { value = value.dropFirst() }
            lines.append(ConfigLine(key: key, value: String(value),
                                    section: section(of: key)))
        }
        return lines.isEmpty ? nil : lines
    }

    /// The heading a key is drawn under — **`.brew` for a key this table does
    /// not know.**
    ///
    /// Not a drop. Homebrew adds keys between releases (`Core cask tap` and
    /// `Metal Toolchain` are both here now and are in neither of the two
    /// captures this feature was written against), and a value nobody sees is
    /// worse than one under an imperfect heading: the person copying this for a
    /// bug report gets the whole document either way, and the one reading it on
    /// screen at least gets the line. `.brew` is the fallback because it is the
    /// group `brew config` is mostly about.
    static func section(of key: String) -> ConfigSection { sections[key] ?? .brew }

    /// Key to heading, hand-written, **beside the parser that reads it** — a
    /// list of names living next to the thing it names rather than becoming a
    /// comment somewhere else. `BrewConfigParserTests` names every key this Mac
    /// produced and fails on any of them this table stops knowing.
    ///
    /// Captured 2026-09-15, Homebrew 7.0.1:
    ///
    ///     $ /opt/homebrew/bin/brew config > /tmp/cfg.out 2> /tmp/cfg.err
    ///     exit=0   555 /tmp/cfg.out   0 /tmp/cfg.err
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
        // What it builds and downloads with. `Metal Toolchain` is here rather
        // than under the machine for the reason `Clang` is: brew reports it as
        // a toolchain it may compile through, not as a fact about the hardware.
        "Clang": .tools,
        "Git": .tools,
        "Curl": .tools,
        "CLT": .tools,
        "Xcode": .tools,
        "Metal Toolchain": .tools,
    ]
}
