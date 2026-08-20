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

    /// **Four, and no more, is a decision.** Every other directive is copied
    /// verbatim, so the set of things Helm can get wrong is the set of things it
    /// can write.
    ///
    /// Beside `Field` rather than inside it: one level of nesting is what this
    /// house's linter allows, and the name reads no worse for it.
    public enum FieldName: String, CaseIterable, Sendable {
        case hostName = "HostName"
        case user = "User"
        case port = "Port"
        case identityFile = "IdentityFile"

        /// `ssh_config` keywords are case-insensitive, and people write them
        /// every way there is.
        static func named(_ keyword: String) -> FieldName? {
            allCases.first { $0.rawValue.lowercased() == keyword.lowercased() }
        }
    }

    /// One of the four directives this module edits.
    public struct Field: Equatable, Sendable {

        public let name: FieldName
        /// The keyword as written, so `hostname` stays lower-case.
        let keyword: String
        let indent: String
        /// What sat between the keyword and the value: spaces, a tab, or an
        /// `=` with whatever surrounds it. `ssh` accepts all three.
        let separator: String
        public internal(set) var value: String
        /// Everything after the value, its line ending included.
        let trailing: String
        /// Where this line sits — and **the answers are three, not two.**
        ///
        /// This was `host: Int?`, and its `nil` meant both «before the first
        /// `Host` line» and «under a `Match`». Those are opposites: a preamble
        /// field applies to *every* connection, and a `Match` field applies to
        /// none this module can name, because the condition that selects it is
        /// a grammar this parser does not read. One `nil` for both is the fold
        /// ARCHITECTURE.md § A nil from a system read is about, and it made the
        /// preamble unreachable — while any attempt to reach it swept the
        /// `Match` block's key into the host above.
        public let scope: Scope
        /// The host block this line belongs to, or nil when it belongs to none.
        /// What an editor may write to; `scope` is what says *why* when it is
        /// nil.
        public var host: Int? {
            if case .host(let index) = scope { return index }
            return nil
        }
        public let index: Int
    }

    /// Which part of the file a field sits in.
    public enum Scope: Equatable, Sendable {
        /// Before the first `Host` line. Legal, and applied to every
        /// connection — and applied *first*, so it wins over a block that sets
        /// the same parameter.
        case preamble
        /// Inside the `Host` block with this index.
        case host(Int)
        /// Inside a `Match` block. It applies when the match condition holds,
        /// and this module can neither show that condition nor evaluate it — so
        /// the field is copied and attributed to nobody. Attributing it to the
        /// `Host` block above would tell somebody a host uses a key it only
        /// uses sometimes.
        case match
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
        ///
        /// The block's **own** lines, which is what an editor may write to. For
        /// what `ssh` will actually use, see `fieldsReaching(host:)`.
        public func fields(ofHost index: Int) -> [Field] {
            fields.filter { $0.host == index }
        }

        /// **Whether the file hands part of itself to files this module has not
        /// read.**
        ///
        /// `Include` is `ssh_config`'s way of splitting a config across a
        /// directory, and everything in those files is invisible here — so a
        /// document carrying one cannot support the sentence «not used by
        /// anything here», which on the keys tab is read as «safe to delete».
        /// The positive answers are unaffected: a key this file names is named
        /// by it whatever else is included.
        ///
        /// `Include` is not one of the four directives this module edits, so it
        /// is a `verbatim` line and is recognised by its keyword.
        public var includesOtherFiles: Bool {
            lines.contains { line in
                guard case .verbatim(let text) = line else { return false }
                return parts(text).map { $0.keyword.lowercased() == "include" } ?? false
            }
        }

        /// Every field `ssh` reads for this host, in the order it reads them:
        /// **the preamble first, then the block's own lines.**
        ///
        /// A directive before the first `Host` line is not «in no block», it is
        /// «in every block» — `Field.scope` says so in its own documentation and
        /// the join dropped every such field on the floor, so a key the whole
        /// file logs in with read as «not used by anything here», which on that
        /// page is the sentence meaning «safe to delete».
        ///
        /// The preamble comes first because `ssh` reads the file top to bottom
        /// and **the first value obtained for a parameter is the one used** —
        /// so a preamble line does not merely apply, it wins.
        public func fieldsReaching(host index: Int) -> [Field] {
            fields.filter { $0.scope == .preamble || $0.scope == .host(index) }
        }
    }

    // MARK: - Reading

    public static func parse(_ text: String) -> Document {
        var lines: [Line] = []
        var hostIndex = 0
        var fieldIndex = 0
        var scope: Scope = .preamble
        for raw in LineEndings.split(text) {
            let body = raw.body
            if let host = host(from: body, ending: raw.ending, index: hostIndex) {
                lines.append(.host(host))
                scope = .host(hostIndex)
                hostIndex += 1
                continue
            }
            // A `Match` closes the block above it without opening one this
            // parser will offer to edit: fields under it belong to nobody, and
            // are copied rather than shown. **Its own scope, not the
            // preamble's** — the preamble reaches every host and a `Match`
            // reaches none this module can name.
            if opensAMatch(body) {
                scope = .match
                lines.append(.verbatim(body + raw.ending))
                continue
            }
            if let field = field(from: body, ending: raw.ending,
                                 scope: scope, index: fieldIndex) {
                lines.append(.field(field))
                fieldIndex += 1
                continue
            }
            lines.append(.verbatim(body + raw.ending))
        }
        return Document(lines: lines)
    }

    /// Splits a directive line into indent, keyword, separator, value and
    /// trailing — or nil when the line holds no keyword at all.
    /// The pieces of a directive line. A struct rather than a tuple: four
    /// members is one past what this house's linter allows, and the reason it
    /// allows two is that a longer tuple is read by position at every call.
    private struct Parts {
        let indent: String
        let keyword: String
        let separator: String
        let rest: String
    }

    private static func parts(_ body: String) -> Parts? {
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
        return Parts(indent: indent, keyword: keyword, separator: separator, rest: rest)
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
                              scope: Scope, index: Int) -> Field? {
        guard let parts = parts(body), let name = FieldName.named(parts.keyword),
              !parts.rest.isEmpty else { return nil }
        let (value, trailing) = split(value: parts.rest)
        return Field(name: name, keyword: parts.keyword, indent: parts.indent,
                     separator: parts.separator, value: value,
                     trailing: trailing + ending, scope: scope, index: index)
    }

    /// The value, and what follows it.
    ///
    /// **A `#` opens a comment only where a token begins**, and is an ordinary
    /// character inside one. Measured against this Mac's own `ssh`, which is
    /// the only authority on it:
    ///
    /// ```
    /// $ printf 'Host box\n  IdentityFile ~/.ssh/my#key\n' > cfg; ssh -G -F cfg box
    /// identityfile ~/.ssh/my#key
    /// $ printf 'Host box\n  IdentityFile ~/.ssh/plain # note\n' > cfg; ssh -G -F cfg box
    /// identityfile ~/.ssh/plain
    /// ```
    ///
    /// Cutting at the first `#` outright was one condition short, and both
    /// halves of the mistake showed at once: the host's row marked a key that
    /// is gone (there is no `my`) and the key `ssh` really uses read «not used
    /// by anything here» — the sentence that means «safe to delete».
    private static func split(value rest: String) -> (value: String, trailing: String) {
        guard let hash = commentStart(in: rest) else {
            // Trailing whitespace belongs to the trailing part, so an edit does
            // not silently strip it.
            let value = String(rest.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
            return (value, String(rest.dropFirst(value.count)))
        }
        let head = String(rest[rest.startIndex..<hash])
        let value = String(head.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
        return (value, String(rest.dropFirst(value.count)))
    }

    /// Where a comment starts: a `#` that opens a token, meaning the line
    /// begins with it or a space or tab sits in front of it. A `#` anywhere
    /// else is part of the value.
    private static func commentStart(in rest: String) -> String.Index? {
        var previous: Character?
        var index = rest.startIndex
        while index < rest.endIndex {
            if rest[index] == "#", previous == nil || previous == " " || previous == "\t" {
                return index
            }
            previous = rest[index]
            index = rest.index(after: index)
        }
        return nil
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
    public static func set(_ value: String, of name: FieldName, ofHost host: Int,
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
