import Foundation

/// `~/.ssh/config` as a document that can be edited without being reformatted.
///
/// **The text is canonical**, exactly as it is for `/etc/hosts` next door: the
/// table on screen is derived from it and an edit re-renders it, so the raw
/// view shows byte-for-byte what will be written.
///
/// This file is a harder guest than the hosts file, and the difference decides
/// the shape here. A hosts file is a list of like lines; a config is **blocks**,
/// and most of what is in a block belongs to `ssh`, not to Helm: `ProxyJump`,
/// `ServerAliveInterval`, `Match` with a shell condition, an `Include` of a
/// whole directory. Helm reads four directives and copies everything else — so
/// `.verbatim` here is not the rare case for junk, it is the ordinary case, and
/// the four fields are the exception.
///
/// `Match` is deliberately **not** a host: its patterns are a different grammar
/// (`exec`, `originalhost`, `user`), the block they open applies conditionally,
/// and a table that listed one beside real hosts would be offering to edit a
/// row whose condition it cannot show. It survives as verbatim like everything
/// else, which is the spec's «shown and not followed» read from the writing
/// end.
public enum SSHConfigFile {

    /// One line, in the order it appeared.
    public enum Line: Equatable, Sendable {
        case host(Host)
        case field(Field)
        case verbatim(String)
    }

    /// A `Host` line: the keyword as it was written, and the patterns after it.
    ///
    /// Every piece of whitespace is kept for the same reason the hosts parser
    /// keeps its columns: an untouched line has to render back to its own
    /// bytes, and a config aligned by hand is how a file somebody maintains
    /// looks.
    public struct Host: Equatable, Sendable {
        /// What the person typed — `Host`, `host`, `HOST`. Case is not
        /// significant to `ssh` and is significant to the person reading the
        /// diff afterwards.
        let keyword: String
        let indent: String
        /// Between the keyword and the first pattern.
        let spacing: String
        /// The patterns, as one string: `build`, or `gate *.example`.
        public internal(set) var patterns: String
        /// Everything after the patterns, its line ending included — a trailing
        /// comment lives here.
        let trailing: String
        /// Where this line sits among the host lines, so a row on screen names
        /// a line rather than a string that may repeat.
        public let index: Int
    }

    /// One of the four directives this module edits.
    public struct Field: Equatable, Sendable {

        /// **Four, and no more, is a decision.** Every other directive is
        /// copied verbatim, so the set of things Helm can get wrong is the set
        /// of things it can write.
        public enum Name: String, CaseIterable, Sendable {
            case hostName = "HostName"
            case user = "User"
            case port = "Port"
            case identityFile = "IdentityFile"

            /// `ssh_config` keywords are case-insensitive, and people write
            /// them every way there is.
            static func named(_ keyword: String) -> Name? {
                allCases.first { $0.rawValue.lowercased() == keyword.lowercased() }
            }
        }

        public let name: Name
        /// The keyword as written, so `hostname` stays lower-case.
        let keyword: String
        let indent: String
        /// What sat between the keyword and the value: spaces, a tab, or an
        /// `=` with whatever surrounds it. `ssh` accepts all three.
        let separator: String
        public internal(set) var value: String
        /// Everything after the value, its line ending included.
        let trailing: String
        /// Which host block this line belongs to, or nil for a field before
        /// the first `Host` line — legal, and applied to every connection.
        public let host: Int?
        public let index: Int
    }

    public struct Document: Equatable, Sendable {
        public internal(set) var lines: [Line]
        init(lines: [Line]) { self.lines = lines }

        public var hosts: [Host] {
            lines.compactMap { if case .host(let host) = $0 { return host } else { return nil } }
        }

        public var fields: [Field] {
            lines.compactMap { if case .field(let field) = $0 { return field } else { return nil } }
        }

        /// The rows the table draws: one host, with the four fields Helm knows
        /// about that were found inside it.
        public func fields(ofHost index: Int) -> [Field] {
            fields.filter { $0.host == index }
        }
    }

    // MARK: - Reading

    public static func parse(_ text: String) -> Document {
        var lines: [Line] = []
        var hostIndex = 0
        var fieldIndex = 0
        var currentHost: Int?
        for raw in splitKeepingEndings(text) {
            let body = raw.body
            if let host = host(from: body, ending: raw.ending, index: hostIndex) {
                lines.append(.host(host))
                currentHost = hostIndex
                hostIndex += 1
                continue
            }
            // A `Match` closes the block above it without opening one this
            // parser will offer to edit: fields under it belong to nobody, and
            // are copied rather than shown.
            if opensAMatch(body) {
                currentHost = nil
                lines.append(.verbatim(body + raw.ending))
                continue
            }
            if let field = field(from: body, ending: raw.ending,
                                 host: currentHost, index: fieldIndex) {
                lines.append(.field(field))
                fieldIndex += 1
                continue
            }
            lines.append(.verbatim(body + raw.ending))
        }
        return Document(lines: lines)
    }

    /// A line, and the ending it had — the same reader the hosts parser uses,
    /// and for the reason recorded there: `components(separatedBy:)` throws the
    /// ending away, so a CRLF file comes back as LF and every line in it reads
    /// as changed. CRLF is one `Character` in Swift, so it is matched as
    /// itself.
    private static func splitKeepingEndings(_ text: String) -> [(body: String, ending: String)] {
        var out: [(String, String)] = []
        var body = ""
        for character in text {
            if character == "\n" || character == "\r\n" || character == "\r" {
                out.append((body, String(character)))
                body = ""
            } else {
                body.append(character)
            }
        }
        // A file whose last line has no ending is a file that must not gain
        // one; the empty tail after a final newline is not a line at all.
        if !body.isEmpty { out.append((body, "")) }
        return out
    }

    /// Splits a directive line into indent, keyword, separator, value and
    /// trailing — or nil when the line holds no keyword at all.
    private static func parts(_ body: String)
        -> (indent: String, keyword: String, separator: String, rest: String)? {
        let indent = String(body.prefix { $0 == " " || $0 == "\t" })
        let afterIndent = String(body.dropFirst(indent.count))
        guard let first = afterIndent.first, first != "#" else { return nil }
        let keyword = String(afterIndent.prefix { $0 != " " && $0 != "\t" && $0 != "=" })
        guard !keyword.isEmpty else { return nil }
        let afterKeyword = String(afterIndent.dropFirst(keyword.count))
        // The separator is whitespace, or whitespace around an `=`. Taken as
        // written so `HostName\t=\tvalue` renders back with both tabs.
        var separator = ""
        var rest = afterKeyword
        var sawEquals = false
        while let character = rest.first {
            if character == " " || character == "\t" {
                separator.append(character); rest.removeFirst()
            } else if character == "=" && !sawEquals {
                sawEquals = true
                separator.append(character); rest.removeFirst()
            } else {
                break
            }
        }
        return (indent, keyword, separator, rest)
    }

    private static func host(from body: String, ending: String, index: Int) -> Host? {
        guard let parts = parts(body), parts.keyword.lowercased() == "host" else { return nil }
        // A `Host` with no patterns is not a block anybody can edit, and `ssh`
        // does not accept it either. Verbatim, so the file keeps whatever it is.
        guard !parts.rest.isEmpty else { return nil }
        let (patterns, trailing) = split(value: parts.rest)
        return Host(keyword: parts.keyword, indent: parts.indent, spacing: parts.separator,
                    patterns: patterns, trailing: trailing + ending, index: index)
    }

    private static func opensAMatch(_ body: String) -> Bool {
        parts(body).map { $0.keyword.lowercased() == "match" } ?? false
    }

    private static func field(from body: String, ending: String,
                              host: Int?, index: Int) -> Field? {
        guard let parts = parts(body), let name = Field.Name.named(parts.keyword),
              !parts.rest.isEmpty else { return nil }
        let (value, trailing) = split(value: parts.rest)
        return Field(name: name, keyword: parts.keyword, indent: parts.indent,
                     separator: parts.separator, value: value,
                     trailing: trailing + ending, host: host, index: index)
    }

    /// The value, and what follows it. A value runs to the first whitespace
    /// that is followed by a `#`, or to the end of the line — `ssh` takes the
    /// rest of the line, and a trailing comment is what people put there.
    private static func split(value rest: String) -> (value: String, trailing: String) {
        guard let hash = rest.firstIndex(of: "#") else {
            // Trailing whitespace belongs to the trailing part, so an edit does
            // not silently strip it.
            let value = String(rest.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
            return (value, String(rest.dropFirst(value.count)))
        }
        let head = String(rest[rest.startIndex..<hash])
        let value = String(head.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
        return (value, String(rest.dropFirst(value.count)))
    }

    // MARK: - Writing

    public static func render(_ document: Document) -> String {
        document.lines.map(render).joined()
    }

    private static func render(_ line: Line) -> String {
        switch line {
        case .verbatim(let text): return text
        case .host(let host):
            return host.indent + host.keyword + host.spacing + host.patterns + host.trailing
        case .field(let field):
            return field.indent + field.keyword + field.separator + field.value + field.trailing
        }
    }

    // MARK: - Editing

    /// Rewrites one field of one host block, and answers whether it did.
    ///
    /// **The value is checked here and nowhere else**, which is why the stored
    /// properties are `public internal(set)` and a caller outside the engine
    /// cannot assign one. A directive's value is a line fragment, and three
    /// kinds of fragment stop being one:
    ///
    /// - **A line break** makes it two directives. `IdentityFile ~/.ssh/id` and
    ///   a second line reading `ProxyCommand nc somewhere 22` is a command
    ///   `ssh` runs on the person's behalf, written by whoever typed into a
    ///   text field. This is the `/etc/hosts` hazard one file over, arriving
    ///   through the door marked «it is only your own file».
    /// - **A `#`** opens a comment, so everything after it on that line —
    ///   including the comment the person had already written there — stops
    ///   being read.
    /// - **Nothing at all.** `ssh` treats a keyword with no argument as a parse
    ///   error and stops reading the file at that line, so an empty value does
    ///   not clear a setting: it silently drops every block below it.
    ///
    /// Adding a directive the block does not have is a different act — it has a
    /// place in the file to argue about — and this refuses it rather than
    /// guessing where a new line goes.
    @discardableResult
    public static func set(_ value: String, of name: Field.Name, ofHost host: Int,
                           in document: inout Document) -> Bool {
        guard isWritable(value) else { return false }
        guard let position = document.lines.firstIndex(where: { line in
            if case .field(let field) = line, field.name == name, field.host == host {
                return true
            }
            return false
        }) else { return false }
        guard case .field(var field) = document.lines[position] else { return false }
        field.value = value
        document.lines[position] = .field(field)
        return true
    }

    /// What may become a value. Internal rather than private so the refusal has
    /// a test of its own that does not have to build a document to ask.
    static func isWritable(_ value: String) -> Bool {
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !value.contains("#") else { return false }
        return !value.contains(where: \.isNewline)
    }
}
