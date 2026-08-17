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
        public var id: String { "\(address)\u{0}\(names.joined(separator: " "))\u{0}\(index)" }
        /// Position in the document, so two identical entries are still two rows.
        public var index: Int
        public var address: String
        public var names: [String]
        /// The comment after the names, `#` and all, or an empty string.
        public var trailing: String
        /// Whether the line is live. A disabled entry is a commented one.
        public var enabled: Bool
        var leading: String
        var spacing: String
        /// The gap before each name after the first. Short of the names it
        /// separates — a name added to an entry gets a single space — so a
        /// caller changing `names` never has a second array to keep in step.
        var separators: [String]
        var ending: String

        public init(index: Int, address: String, names: [String],
                    trailing: String = "", enabled: Bool = true,
                    leading: String = "", spacing: String = "\t",
                    separators: [String] = [], ending: String = "\n") {
            self.index = index
            self.address = address
            self.names = names
            self.trailing = trailing
            self.enabled = enabled
            self.leading = leading
            self.spacing = spacing
            self.separators = separators
            self.ending = ending
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
        var leading = takeBlanks(&rest)
        var enabled = true
        if rest.hasPrefix("#") {
            enabled = false
            rest = rest.dropFirst()
            leading += "#" + takeBlanks(&rest)
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
                     separators: scanned.separators, ending: ending)
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

    /// Whether a token is an address at all. `inet_pton` answers for both
    /// families and knows the forms a hand-written check gets wrong; the zone
    /// suffix of a link-local address (`fe80::1%lo0`) is stripped first,
    /// because it is a scope and not part of the address.
    public static func isAddress(_ token: String) -> Bool {
        let bare = token.split(separator: "%", maxSplits: 1).first.map(String.init) ?? token
        var v4 = in_addr()
        if bare.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 { return true }
        var v6 = in6_addr()
        return bare.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1
    }

    // MARK: - Writing

    public static func render(_ document: Document) -> String {
        document.lines.reduce(into: "") { text, line in
            switch line {
            case .verbatim(let raw):
                text += raw
            case .entry(let entry):
                text += entry.leading + entry.address + entry.spacing
                    + entry.namesRendered + entry.trailing + entry.ending
            }
        }
    }
}
