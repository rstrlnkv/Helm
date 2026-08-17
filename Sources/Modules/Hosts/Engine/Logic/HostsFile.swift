import Foundation

/// `/etc/hosts` as a document that can be edited without being reformatted.
///
/// **The text is canonical.** The table on screen is derived from it and an
/// edit re-renders it, so the raw view shows byte-for-byte what will be
/// written. Two views of one file cannot disagree when only one of them is the
/// file.
///
/// Everything the parser cannot read — Apple's header, blank lines, a junk
/// line, an unfamiliar comment — is kept as `.verbatim` and written back
/// exactly as it came in, including its line ending.
public enum HostsFile {

    /// One line, in the order it appeared.
    public enum Line: Equatable, Sendable {
        case entry(Entry)
        case verbatim(String)
    }

    /// A mapping the table can show.
    ///
    /// `spacing` is what sat between the address and the first name,
    /// `separators` is what sat between one name and the next, and `trailing`
    /// is everything after the last name. All three are kept so an untouched
    /// entry renders back to its own bytes — an editor that normalises a tab
    /// to a space has rewritten a line it was only asked to read, and aligned
    /// columns are how a hand-maintained hosts file looks.
    public struct Entry: Equatable, Sendable, Identifiable {
        /// The row's position, and nothing about what it says.
        ///
        /// An id copied from the content is not an identity: SwiftUI destroys
        /// and rebuilds a `ForEach` row whose id changed, taking `@FocusState`
        /// and the half-typed text with it, so a field bound to `address` would
        /// lose the caret after one keystroke. `index` is unique within a parse
        /// and unchanged by an edit, which is both halves of what an id owes.
        public var id: Int { index }
        /// Position in the document, so two identical entries are still two rows.
        public var index: Int
        public var address: String
        public var names: [String]
        /// The comment after the names, `#` and all, or an empty string.
        public var trailing: String
        /// **Whether the line is live, and the only thing that decides.**
        ///
        /// The `#` of a disabled line is not kept in `leading`, where it would
        /// be a second field saying the same thing: an `Entry` built by a view
        /// model with `enabled: false` was written as a live mapping for as
        /// long as those two existed side by side. This file goes to `/etc`
        /// with administrator rights, so «the model says off and the file says
        /// on» is the one disagreement it can least afford.
        public var enabled: Bool
        /// Indentation only — never the comment marker.
        var leading: String
        /// How this line spelled its `#`, kept so a file Helm only read comes
        /// back with its own spelling. Consulted for *how* a disabled line is
        /// written, never for *whether* it is one, and ignored entirely while
        /// `enabled` is true.
        var disabledMark: String
        var spacing: String
        /// The gap before each name after the first. Short of the names it
        /// separates — a name added to an entry gets a single space — so a
        /// caller changing `names` never has a second array to keep in step.
        var separators: [String]
        var ending: String

        /// What a caller outside the engine can build: a mapping, a comment,
        /// and whether it is live.
        ///
        /// The whitespace a line was written with is deliberately not on offer.
        /// `leading` beside `enabled` is a second way to say whether a mapping
        /// is commented out, and a public initializer taking both leaves the
        /// disagreement representable from the one target that will be building
        /// entries — which is where it would come from.
        public init(index: Int, address: String, names: [String],
                    trailing: String = "", enabled: Bool = true) {
            self.init(index: index, address: address, names: names,
                      trailing: trailing, enabled: enabled, leading: "",
                      spacing: "\t", separators: [], disabledMark: "", ending: "\n")
        }

        /// Everything a line was made of, which only the parser knows.
        init(index: Int, address: String, names: [String], trailing: String,
             enabled: Bool, leading: String, spacing: String,
             separators: [String], disabledMark: String, ending: String) {
            self.index = index
            self.address = address
            self.names = names
            self.trailing = trailing
            self.enabled = enabled
            self.leading = leading
            self.spacing = spacing
            self.separators = separators
            self.disabledMark = disabledMark
            self.ending = ending
        }

        /// What stands between the indentation and the address: nothing while
        /// the mapping is live, and this line's own `#` when it is not. An
        /// entry switched off by a caller that never read one from a file is
        /// written the way macOS writes its own.
        var mark: String {
            guard !enabled else { return "" }
            return disabledMark.isEmpty ? "# " : disabledMark
        }

        /// The names as they sat in the file.
        var namesRendered: String {
            names.enumerated().reduce(into: "") { text, pair in
                if pair.offset > 0 {
                    text += pair.offset - 1 < separators.count ? separators[pair.offset - 1] : " "
                }
                text += pair.element
            }
        }
    }

    public struct Document: Equatable, Sendable {
        public var lines: [Line]
        public init(lines: [Line]) { self.lines = lines }

        /// The rows the table draws, in file order.
        public var entries: [Entry] {
            lines.compactMap { if case .entry(let entry) = $0 { return entry } else { return nil } }
        }
    }

    // MARK: - Reading

    public static func parse(_ text: String) -> Document {
        var lines: [Line] = []
        var index = 0
        for raw in splitKeepingEndings(text) {
            if let entry = entry(from: raw.body, index: index, ending: raw.ending) {
                lines.append(.entry(entry))
                index += 1
            } else {
                lines.append(.verbatim(raw.body + raw.ending))
            }
        }
        return Document(lines: lines)
    }

    /// A line, and the ending it had. `components(separatedBy:)` throws the
    /// ending away, which is how a CRLF file comes back as LF and every line
    /// in it reads as changed.
    ///
    /// CRLF is one `Character` in Swift — a grapheme cluster — so it is matched
    /// as itself. A reader that looks for `"\r"` and peeks ahead for `"\n"`
    /// matches neither half and swallows a CRLF file whole, and the round trip
    /// cannot see it do that: an unsplit file is a file nobody reformatted.
    private static func splitKeepingEndings(_ text: String) -> [(body: String, ending: String)] {
        var out: [(body: String, ending: String)] = []
        var body = ""
        for character in text {
            if character == "\r\n" || character == "\n" || character == "\r" {
                out.append((body, String(character)))
                body = ""
            } else {
                body.append(character)
            }
        }
        if !body.isEmpty { out.append((body, "")) }
        return out
    }

    private static func entry(from body: String, index: Int, ending: String) -> Entry? {
        // A disabled entry is a commented line that still reads as one. Any
        // other `#` line is somebody's comment and stays verbatim.
        var rest = Substring(body)
        let leading = takeBlanks(&rest)
        var enabled = true
        var disabledMark = ""
        if rest.hasPrefix("#") {
            enabled = false
            rest = rest.dropFirst()
            disabledMark = "#" + takeBlanks(&rest)
        }
        guard !rest.isEmpty else { return nil }

        // Split off a trailing comment before anything else: a `#` inside a
        // line is a comment wherever it sits.
        var trailing = ""
        if let hash = rest.firstIndex(of: "#") {
            trailing = String(rest[hash...])
            rest = rest[..<hash]
        }

        guard let addressEnd = rest.firstIndex(where: isBlank) else { return nil }
        let address = String(rest[..<addressEnd])
        guard isAddress(address) else { return nil }

        var afterAddress = rest[addressEnd...]
        let spacing = takeBlanks(&afterAddress)
        let scanned = scanNames(afterAddress)
        guard !scanned.names.isEmpty else { return nil }

        return Entry(index: index, address: address, names: scanned.names,
                     trailing: scanned.tail + trailing, enabled: enabled,
                     leading: leading, spacing: spacing,
                     separators: scanned.separators, disabledMark: disabledMark,
                     ending: ending)
    }

    /// The names, the gaps between them, and whatever whitespace ran on after
    /// the last one.
    private struct ScannedNames {
        var names: [String] = []
        var separators: [String] = []
        var tail = ""
    }

    /// Splitting on whitespace and re-joining with one space is what collapses
    /// somebody's aligned columns, and the file it reformats is one Helm was
    /// only asked to read — so the gaps are read out with the names.
    private static func scanNames(_ text: Substring) -> ScannedNames {
        var scanned = ScannedNames()
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let nameEnd = text[cursor...].firstIndex(where: isBlank) ?? text.endIndex
            scanned.names.append(String(text[cursor..<nameEnd]))
            guard nameEnd < text.endIndex else { break }
            let gapEnd = text[nameEnd...].firstIndex(where: { !isBlank($0) }) ?? text.endIndex
            // A run of whitespace after the last name belongs to the comment's
            // side, so it survives with the comment rather than being trimmed.
            guard gapEnd < text.endIndex else {
                scanned.tail = String(text[nameEnd...])
                break
            }
            scanned.separators.append(String(text[nameEnd..<gapEnd]))
            cursor = gapEnd
        }
        return scanned
    }

    private static func isBlank(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    /// Cuts the run of blanks off the front and hands it back. Every piece of
    /// whitespace in this file is somebody's, so it is moved, never dropped.
    private static func takeBlanks(_ text: inout Substring) -> String {
        let end = text.firstIndex(where: { !isBlank($0) }) ?? text.endIndex
        defer { text = text[end...] }
        return String(text[..<end])
    }

    // MARK: - Addresses
    //
    // **Two questions, two predicates, and they differ on purpose.** libc reads
    // one token two ways, measured here on macOS 27, 2026-08-18:
    //
    //     inet_pton(AF_INET, "0177.0.0.1") -> 177.0.0.1
    //     inet_aton(         "0177.0.0.1") -> 127.0.0.1     // octal
    //     inet_pton(AF_INET, "010.0.0.1")  -> 10.0.0.1
    //     inet_aton(         "010.0.0.1")  -> 8.0.0.1
    //     inet_pton(AF_INET, "127.1")      -> refused
    //     inet_aton(         "127.1")      -> 127.0.0.1
    //
    // Do not fold these back into one predicate. Reading is generous because a
    // mapping missing from the table is a mapping nobody can switch off, and
    // `0177.0.0.1 evil.example` is the loopback wearing an innocent face —
    // exactly the line a person most needs shown. Writing is strict because
    // Helm cannot know which parser reads the file it produces, so it must
    // never *create* a token whose meaning depends on that.

    /// Whether a token is an address to *somebody* — the parse-time question,
    /// "is this line a row?". Anything `inet_pton` or `inet_aton` accepts.
    public static func isAddress(_ token: String) -> Bool {
        guard isPlausibleToken(token) else { return false }
        let bare = withoutZone(token)
        return parsesStrictly(bare) || parsesTheClassicWay(bare)
    }

    /// Whether Helm may *write* this token — the field-editor question. Strict
    /// where `isAddress` is generous: `inet_pton` only, and no decimal padded
    /// with a leading zero, because that is the token the two parsers read
    /// differently.
    public static func isWritableAddress(_ token: String) -> Bool {
        guard isPlausibleToken(token), !hasPaddedDecimal(token) else { return false }
        if let zone = zone(of: token) {
            guard !zone.isEmpty, zone.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        }
        return parsesStrictly(withoutZone(token))
    }

    /// What neither predicate will answer about. `withCString` hands C a buffer
    /// that still holds an embedded NUL and C stops there, so the answer would
    /// be about a prefix rather than about the token that gets written; and
    /// `inet_aton` accepts a trailing space (measured), which would vouch for
    /// one token where the file holds two.
    private static func isPlausibleToken(_ token: String) -> Bool {
        !token.isEmpty && !token.contains { $0.isWhitespace || $0 == "\u{0}" }
    }

    /// The scope of a link-local address (`fe80::1%lo0`) is not part of the
    /// address, so it is cut off before either parser sees it.
    private static func withoutZone(_ token: String) -> String {
        String(token.prefix(while: { $0 != "%" }))
    }

    private static func zone(of token: String) -> String? {
        guard let percent = token.firstIndex(of: "%") else { return nil }
        return String(token[token.index(after: percent)...])
    }

    private static func parsesStrictly(_ token: String) -> Bool {
        var v4 = in_addr()
        if token.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 { return true }
        var v6 = in6_addr()
        return token.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1
    }

    /// `inet_aton` is what much older software reads a hosts file with, and it
    /// takes `127.1`, `2130706433` and `0x7f.1` as the loopback.
    private static func parsesTheClassicWay(_ token: String) -> Bool {
        var v4 = in_addr()
        return token.withCString({ inet_aton($0, &v4) }) == 1
    }

    /// Whether a dotted decimal in the token is padded with a leading zero.
    ///
    /// Only the dotted tail is read, so an IPv6 group written `0001` is left
    /// alone — no parser reads a hex group as octal — while the embedded IPv4
    /// of `::ffff:010.0.0.1`, which `inet_pton` does accept, is caught.
    private static func hasPaddedDecimal(_ token: String) -> Bool {
        let tail = token.split(separator: ":").last.map(String.init) ?? token
        guard tail.contains(".") else { return false }
        return tail.split(separator: ".", omittingEmptySubsequences: false)
            .contains { $0.count > 1 && $0.hasPrefix("0") }
    }

    // MARK: - Writing

    public static func render(_ document: Document) -> String {
        document.lines.reduce(into: "") { text, line in
            switch line {
            case .verbatim(let raw):
                text += raw
            case .entry(let entry):
                text += entry.leading + entry.mark + entry.address + entry.spacing
                    + entry.namesRendered + entry.trailing + entry.ending
            }
        }
    }
}
