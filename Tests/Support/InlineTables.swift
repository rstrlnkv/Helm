import Foundation
import HelmRuntime
import HelmUI

/// Every inline `[AppLanguage: String]` table Swift's interpolation exception
/// (CLAUDE.md) allows in place of the eight `.lproj` files — found by the
/// literal `[.lang:` rather than by `L(`, because a table does not have to be
/// passed to `L` at all: it can be a `let` binding read a few lines later, or a
/// `return`.
///
/// Reads `SwiftSource.uncommented(under:)`, never the raw file — this
/// repository writes backticked names and quoted Swift inside doc comments on
/// purpose, and a table quoted there is not a table the app carries.
///
/// The boundary this type keeps: it hands back data — `Table`, `Row`,
/// `SwiftSource.Literal` — and a thrown error, never a judgement. Whether seven
/// languages are present, whether French spaces its punctuation the way macOS
/// does, and whether a mark belongs to another language are asked by the tests
/// that already own those rules for the `.lproj` files.
public enum InlineTables {

    /// One row of a table — one language's expression, and the literals in it.
    public struct Row: Sendable, Equatable {
        public let language: AppLanguage
        /// The row's own line — a one-line table puts every row on one line, so
        /// this can equal `Table.line` for every row of it.
        public let line: Int
        /// What is written after the language and its colon, trimmed.
        public let expression: String
        /// Every string literal the expression holds, in order — `[]` for a
        /// row like `.ru: ru`, whose value is a bare identifier and not a
        /// literal at all.
        public let literals: [SwiftSource.Literal]

        public init(language: AppLanguage, line: Int, expression: String,
                    literals: [SwiftSource.Literal]) {
            self.language = language
            self.line = line
            self.expression = expression
            self.literals = literals
        }
    }

    /// One table, wherever it was written.
    public struct Table: Sendable, Equatable {
        public let path: String
        /// The line of the table's own `[`.
        public let line: Int
        /// The line of the matching `]` — equal to `line` for a one-line table.
        public let closingLine: Int
        /// The raw text of `L("…"` when the table is that call's second
        /// argument and the first is a plain literal; `nil` for a `let`
        /// binding, a `return`, or a first argument that is not a literal
        /// (`L(condition ? "a" : "b", [ … ])`) — none of which name a key this
        /// reader can judge for an interpolation marker.
        public let key: String?
        public let rows: [Row]

        public init(path: String, line: Int, closingLine: Int, key: String?, rows: [Row]) {
            self.path = path
            self.line = line
            self.closingLine = closingLine
            self.key = key
            self.rows = rows
        }
    }

    /// A floor under the count every reader finds in the real tree, so a reader
    /// pointed at the wrong directory — or one whose walk has quietly stopped
    /// matching anything — fails loudly rather than reporting an empty tree as
    /// clean.
    public static let floor = 90

    /// Every table under a repository directory — walked, read and parsed once
    /// a process, the way `SwiftSource.code(under:)` is.
    public static func tables(under directory: String) throws -> [Table] {
        try memo.value(for: directory) {
            Result {
                try SwiftSource.uncommented(under: directory).flatMap {
                    try tables(in: $0.text, path: $0.path)
                }
            }
        }.get()
    }

    /// The same, against a string already read as `SwiftSource.uncommented(_:)`
    /// reads one — for a fixture, and for the walk above.
    public static func tables(in uncommented: String, path: String) throws -> [Table] {
        // A fast no: a file naming none of the eight languages as `.lang`
        // followed, anywhere after optional whitespace, by `:` has no table
        // — the same reasoning as `SwiftSource.callSites`'s own fast no, and
        // spaced loosely enough that `[.ru : "R", …]` still trips it, since a
        // spelling this only has to admit is one it must never say no to.
        guard opensAnyTable(uncommented) else { return [] }

        let characters = Array(uncommented)
        var out: [Table] = []
        var index = 0
        // The most recently closed literal — the forward-found boundary a
        // table's own key is read against below, in place of the backward
        // bracket count that used to corrupt itself on a key holding an
        // unbalanced `(`, `[` or `{` of its own.
        var lastLiteral: (start: Int, end: Int)?
        while index < characters.count {
            if isStringLiteralStart(characters, index) {
                let start = index
                index = try SwiftSource.endOfLiteral(characters, index, path: path)
                lastLiteral = (start, index)
                continue
            }
            guard characters[index] == "[", opensATable(characters, at: index) else {
                index += 1
                continue
            }
            let (entries, close) = try splitEntries(characters, openBracket: index, path: path)
            var rows: [Row] = []
            for (start, end) in entries {
                let (language, keyStart, valueStart) = try rowLanguage(characters, start: start,
                                                                        end: end, path: path)
                let expression = String(characters[valueStart..<end])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                rows.append(Row(language: language, line: lineOf(characters, keyStart),
                                expression: expression,
                                literals: try SwiftSource.literals(in: expression, path: path)))
            }
            out.append(Table(path: path, line: lineOf(characters, index),
                             closingLine: lineOf(characters, close),
                             key: key(of: characters, openBracket: index, precedingLiteral: lastLiteral),
                             rows: rows))
            index = close + 1
        }
        return out
    }

    private static let memo = LockedMemo<String, Result<[Table], any Error>>()

    // MARK: - Recognising a table

    /// Whether `text` names any of the eight languages as `.lang`, followed —
    /// anywhere after optional whitespace — by `:`. The fast no above this
    /// walk: exact enough to skip a file with no table at all, loose enough
    /// never to say no of one that has it, so `[.ru : "R", …]`, spaced before
    /// every colon, still trips it.
    private static func opensAnyTable(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return languagePatterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    private static let languagePatterns: [NSRegularExpression] = AppLanguage.allCases.compactMap {
        try? NSRegularExpression(pattern: "\\.\($0.rawValue)\\s*:")
    }

    /// Whether, skipping whitespace after `[`, the text reads `.lang:` for a
    /// language `AppLanguage` actually declares — the type name spelled out in
    /// full before the first row's own dot (`AppLanguage.ru: "R"`) is legal
    /// Swift and skipped the same way `rowLanguage` skips it on any row.
    private static func opensATable(_ characters: [Character], at open: Int) -> Bool {
        var i = open + 1
        while i < characters.count, characters[i].isWhitespace { i += 1 }
        i = skippingAppLanguagePrefix(characters, i, limit: characters.count)
        guard i < characters.count, characters[i] == "." else { return false }
        i += 1
        var word = ""
        while i < characters.count, characters[i].isLetter { word.append(characters[i]); i += 1 }
        guard AppLanguage(rawValue: word) != nil else { return false }
        while i < characters.count, characters[i].isWhitespace { i += 1 }
        return i < characters.count && characters[i] == ":"
    }

    /// `i`, advanced past a leading `AppLanguage` if `characters` spells it
    /// there — up to but not past the `.` that follows, so the caller reads
    /// the same `.lang` either way, whether or not the type name was there to
    /// skip. Legal on any row: Swift only requires the type name once and
    /// never forbids repeating it.
    private static func skippingAppLanguagePrefix(_ characters: [Character], _ i: Int, limit: Int) -> Int {
        let word = Array("AppLanguage")
        guard i + word.count < limit, Array(characters[i..<(i + word.count)]) == word,
              characters[i + word.count] == "."
        else { return i }
        return i + word.count
    }

    /// The row entries between `[` and its matching `]`, split at depth-one
    /// commas — a literal is skipped whole, so a `,` or a bracket inside one
    /// (a comment already blanked by `uncommented`, or an interpolation) is
    /// never read as the table's own.
    private static func splitEntries(_ characters: [Character], openBracket: Int,
                                     path: String) throws -> (entries: [(Int, Int)], close: Int) {
        var depth = 1
        var index = openBracket + 1
        var start = index
        var entries: [(Int, Int)] = []
        while index < characters.count {
            if isStringLiteralStart(characters, index) {
                index = try SwiftSource.endOfLiteral(characters, index, path: path)
                continue
            }
            let character = characters[index]
            if character == "[" || character == "(" || character == "{" {
                depth += 1
                index += 1
                continue
            }
            if character == "]" || character == ")" || character == "}" {
                depth -= 1
                if depth == 0 {
                    let text = String(characters[start..<index])
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        entries.append((start, index))
                    }
                    return (entries, index)
                }
                index += 1
                continue
            }
            if character == ",", depth == 1 {
                entries.append((start, index))
                index += 1
                start = index
                continue
            }
            index += 1
        }
        throw UISources.Failure("\(path):\(lineOf(characters, openBracket)) — an unclosed table")
    }

    /// The language, the index of its own `.`, and the index one past its `:`
    /// — for one row entry. `keyStart` is reported separately from `start`
    /// because a multi-line table's entry starts right after the *previous*
    /// row's comma, which sits on the previous line; the row's own line is the
    /// one its `.lang` is written on. A row may spell the type out in full
    /// (`AppLanguage.ru: "R"`) the same as `opensATable` allows on the first
    /// one — Swift never forbids repeating a type name it does not require.
    private static func rowLanguage(_ characters: [Character], start: Int, end: Int,
                                    path: String) throws -> (language: AppLanguage,
                                                             keyStart: Int, valueStart: Int) {
        var i = start
        while i < end, characters[i].isWhitespace { i += 1 }
        let keyStart = i
        i = skippingAppLanguagePrefix(characters, i, limit: end)
        guard i < end, characters[i] == "." else {
            throw UISources.Failure("\(path):\(lineOf(characters, keyStart)) — a table row does not "
                                    + "begin with a language case")
        }
        i += 1
        var word = ""
        while i < end, characters[i].isLetter { word.append(characters[i]); i += 1 }
        guard let language = AppLanguage(rawValue: word) else {
            throw UISources.Failure("\(path):\(lineOf(characters, keyStart)) — \"\(word)\" is not an "
                                    + "AppLanguage case")
        }
        while i < end, characters[i].isWhitespace { i += 1 }
        guard i < end, characters[i] == ":" else {
            throw UISources.Failure("\(path):\(lineOf(characters, keyStart)) — \(language.rawValue)'s "
                                    + "row has no \":\"")
        }
        return (language, keyStart, i + 1)
    }

    /// `L("…"` immediately before the table, read back as the raw text between
    /// its quotes — `nil` when the table is not that call's second argument, or
    /// when the first argument is not, whole, a single literal.
    ///
    /// Forward, not back: `precedingLiteral` is the literal the main walk in
    /// `tables(in:)` most recently closed, found going forward the same way
    /// every literal in this reader is — `SwiftSource.endOfLiteral` skips it
    /// as one token, brackets inside it and all. The walk this replaced went
    /// backward from the table's own `[`, counting `(`, `[` and `{` across
    /// whatever text it crossed on the way — including the key literal's own
    /// characters — so a key like `"Step 1)"` unbalanced the count and read
    /// as no key at all. Reading the literal's boundary forward means there is
    /// nothing left to count: what sits between its end and the table, and
    /// what sits before its start, are each a handful of characters checked
    /// directly.
    private static func key(of characters: [Character], openBracket: Int,
                            precedingLiteral: (start: Int, end: Int)?) -> String? {
        guard let literal = precedingLiteral else { return nil }

        // Nothing but the argument comma and whitespace between the literal
        // and the table — anything else means this literal is not the table's
        // own key, whatever it is instead.
        var i = literal.end
        while i < openBracket, characters[i].isWhitespace { i += 1 }
        guard i < openBracket, characters[i] == "," else { return nil }
        i += 1
        while i < openBracket, characters[i].isWhitespace { i += 1 }
        guard i == openBracket else { return nil }

        // And nothing but whitespace between `L(` and the literal.
        var j = literal.start - 1
        while j >= 0, characters[j].isWhitespace { j -= 1 }
        guard j >= 1, characters[j] == "(", characters[j - 1] == "L" else { return nil }
        let before = j - 2 >= 0 ? characters[j - 2] : nil
        guard before == nil
            || !(before!.isLetter || before!.isNumber || before! == "_" || before! == ".")
        else { return nil }

        let firstArgument = String(characters[literal.start..<literal.end])
        // Excludes a raw (`#"…"#`) or triple-quoted key, the same as the walk
        // this replaced did: the interpolation exception this key exists to
        // justify is written `\(`, which neither spelling carries unescaped.
        guard firstArgument.range(of: #"^"(?:[^"\\]|\\.)*"$"#, options: .regularExpression) != nil
        else { return nil }
        return String(firstArgument.dropFirst().dropLast())
    }

    // MARK: - Skipping a literal structurally

    /// Whether `characters[index]` opens a string literal — `"`, or `#`
    /// followed eventually by `"`.
    private static func isStringLiteralStart(_ characters: [Character], _ index: Int) -> Bool {
        guard index < characters.count else { return false }
        if characters[index] == "\"" { return true }
        guard characters[index] == "#" else { return false }
        var i = index
        while i < characters.count, characters[i] == "#" { i += 1 }
        return i < characters.count && characters[i] == "\""
    }

    private static func lineOf(_ characters: [Character], _ index: Int) -> Int {
        characters[..<index].filter { $0 == "\n" }.count + 1
    }
}
