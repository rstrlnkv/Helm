import Foundation

/// Swift read as text, for the checks that pin something no type system says.
///
/// `RepoSource` answers *which* files and hands back their lines; this answers
/// what is in one. The family it serves is already large — an event name that
/// must not be a literal, a list that must agree with the tree, a control that
/// must be reachable from the keyboard — and two of them now need more than a
/// line at a time: a call whose arguments span four lines, and the body of one
/// function so a rule can be about what that function does.
///
/// **`RepoSource.code` is not enough, and it is not wrong.** It strips a comment
/// tail from one line, which is exactly right for a scan that reads a line at a
/// time and is why every such scan uses it. It cannot see that a `"""` block
/// spans lines, or that a `//` inside a string is not a comment. The first cost
/// a real finding: the keychain-port guard reported two of its own fixtures —
/// Swift quoted inside a `"""` — as offences in `Tests/`, and it did that on the
/// first run it was ever given.
public enum SwiftSource {

    // MARK: - Reading it as the compiler roughly would

    /// `source` with comments and the *insides* of string literals blanked, and
    /// every newline kept where it was — so a finding can still name a line.
    ///
    /// One pass rather than a line filter, because both of the things it removes
    /// can span lines. Raw strings (`#"…"#`, `#"""…"""#`) are recognised, because
    /// this repository writes its regular expressions that way and they are full
    /// of the punctuation every scan below counts.
    public static func code(_ source: String) -> String {
        var out = ""
        var characters = Array(source)[...]
        func take(_ count: Int) -> String {
            let taken = String(characters.prefix(count))
            characters = characters.dropFirst(count)
            return taken
        }
        /// Everything up to `close`, blanked but for its newlines.
        func skip(to close: [Character], escaping: Bool) {
            while !characters.isEmpty {
                if escaping, characters.first == "\\" {
                    _ = take(2)
                    continue
                }
                if characters.starts(with: close) {
                    _ = take(close.count)
                    return
                }
                if take(1) == "\n" { out.append("\n") }
            }
        }
        while !characters.isEmpty {
            if characters.starts(with: Array("//")) {
                skip(to: ["\n"], escaping: false)
                out.append("\n")
            } else if characters.starts(with: Array("/*")) {
                _ = take(2)
                skip(to: Array("*/"), escaping: false)
            } else if characters.starts(with: Array("#\"\"\"")) {
                _ = take(4)
                skip(to: Array("\"\"\"#"), escaping: false)
            } else if characters.starts(with: Array("#\"")) {
                _ = take(2)
                skip(to: Array("\"#"), escaping: false)
            } else if characters.starts(with: Array("\"\"\"")) {
                _ = take(3)
                skip(to: Array("\"\"\""), escaping: true)
            } else if characters.first == "\"" {
                _ = take(1)
                skip(to: ["\""], escaping: true)
            } else {
                out.append(take(1))
            }
        }
        return out
    }

    // MARK: - Call sites

    /// One call, with its arguments split at the commas of its own depth.
    public struct Call: Sendable, Equatable {
        public let line: Int
        /// Where the callee's name starts, so a caller can ask what encloses it.
        public let characterOffset: Int
        public let arguments: [String]

        public init(line: Int, characterOffset: Int, arguments: [String]) {
            self.line = line
            self.characterOffset = characterOffset
            self.arguments = arguments
        }

        /// The labels it names, in order. A positional argument contributes
        /// nothing, which is right: nothing at a call site can name it.
        public var names: [String] { arguments.compactMap(Self.name(of:)) }

        private static func name(of argument: String) -> String? {
            let head = argument.prefix { $0 != ":" && $0 != "(" && $0 != "\n" }
            guard head.count < argument.count,
                  argument[argument.index(argument.startIndex, offsetBy: head.count)] == ":"
            else { return nil }
            let word = head.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, word.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
            else { return nil }
            return word
        }
    }

    /// Every call of `callee` in `source`.
    ///
    /// A hand walk rather than a regular expression, because the arguments span
    /// lines, nest, and hold parentheses inside string literals — all three occur
    /// in this tree, and a pattern that got any of them wrong would drop a call
    /// site *silently*, which is the one failure mode a guard must not have.
    ///
    /// - Parameter wholeWords: whether a longer name ending in `callee` counts.
    ///   True for a type — `FakeDuplicatesViewModel(` is not
    ///   `DuplicatesViewModel(` — and false for `init`, which is always preceded
    ///   by something.
    public static func callSites(of callee: String, in source: String,
                                 wholeWords: Bool = true) -> [Call] {
        var out: [Call] = []
        let characters = Array(source)
        let needle = Array(callee + "(")
        var index = 0
        while index + needle.count <= characters.count {
            defer { index += 1 }
            guard Array(characters[index..<(index + needle.count)]) == needle else { continue }
            if wholeWords, index > 0 {
                let before = characters[index - 1]
                guard !(before.isLetter || before.isNumber || before == "_" || before == ".")
                else { continue }
            }
            guard let arguments = split(from: index + needle.count - 1, in: characters)
            else { continue }
            out.append(Call(line: characters[..<index].filter { $0 == "\n" }.count + 1,
                            characterOffset: index, arguments: arguments))
        }
        return out
    }

    /// The arguments of the call whose `(` is at `open`, split at depth one.
    ///
    /// Nil when the call is not closed inside `characters` — a truncated read
    /// rather than a call with no arguments, and the difference matters, because
    /// the second would excuse the site.
    private static func split(from open: Int, in characters: [Character]) -> [String]? {
        var depth = 0
        var current = ""
        var out: [String] = []
        var index = open
        while index < characters.count {
            let character = characters[index]
            // A literal is copied whole and never inspected: its parentheses are
            // not the call's. Redundant once `code(_:)` has blanked the insides —
            // and kept anyway, because this is callable without it and a reader
            // that is only correct on pre-processed input is one somebody will
            // use on the other kind.
            guard character != "\"" else {
                let end = endOfString(from: index, in: characters)
                current += String(characters[index..<end])
                index = end
                continue
            }
            index += 1
            switch character {
            case "(", "[", "{":
                depth += 1
                if depth > 1 { current.append(character) }
            case ")", "]", "}":
                depth -= 1
                guard depth > 0 else {
                    let last = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    return last.isEmpty ? out : out + [last]
                }
                current.append(character)
            case "," where depth == 1:
                out.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            default:
                current.append(character)
            }
        }
        return nil
    }

    /// One past the closing quote of the literal that starts at `open`, or the
    /// end of the input for one that is never closed.
    private static func endOfString(from open: Int, in characters: [Character]) -> Int {
        var index = open + 1
        while index < characters.count {
            if characters[index] == "\\" { index += 2; continue }
            if characters[index] == "\"" { return index + 1 }
            index += 1
        }
        return characters.count
    }

    // MARK: - Modifier chains

    /// The SwiftUI modifier chain the line at `index` belongs to, by brace
    /// depth rather than by indent.
    ///
    /// **Two accessibility guards need exactly this and it was written twice.**
    /// `KeyboardReachableControlsTests` asks whether a tap gesture's own chain
    /// carries an accessibility action; `AHeadingIsAHeadingToTheRotorTests` asks
    /// whether a heading's own chain carries `.isHeader`. Both must stop at the
    /// end of the chain and not read the control underneath — a chain that ran
    /// on would take the neighbour's trait and report a bare heading as judged.
    ///
    /// **Depth and not indent**, which is the reading the first of the two had
    /// to fix: the closing brace of a multi-line closure is a line no deeper
    /// than the modifier's own that does not begin with a dot, so an indent walk
    /// ended the chain there and could not see a modifier three lines further
    /// down. Any offender could have been hidden from such a rule by pressing
    /// return.
    ///
    /// A blank line or a comment-only line does not end a chain: the modifiers
    /// in this repository are separated by their own explanations. Those
    /// explanations are **stripped from what comes back**, and that is not
    /// optional — both rules are written down in a comment that quotes the very
    /// modifier they look for, so a chain carrying its own comments reports the
    /// reasoning as the finding.
    public static func modifierChain(from index: Int, in lines: [String]) -> String {
        var text = RepoSource.code(lines[index])
        var depth = braces(in: text)
        for raw in lines.dropFirst(index + 1) {
            let code = RepoSource.code(raw)
            let body = code.trimmingCharacters(in: .whitespaces)
            if depth > 0 {
                text += "\n" + code
                depth += braces(in: code)
                continue
            }
            guard body.isEmpty || body.hasPrefix(".") else { break }
            text += "\n" + code
            depth += braces(in: code)
        }
        return text
    }

    private static func braces(in code: String) -> Int {
        code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
    }

    // MARK: - Bodies

    /// A named declaration and the braces around its body.
    public struct Body: Sendable, Equatable {
        public let name: String
        public let open: Int
        public let close: Int

        public var width: Int { close - open }
        public func contains(_ offset: Int) -> Bool { offset > open && offset < close }
    }

    /// Every `class`/`struct`/`actor`/`enum`/`extension`/`protocol` body in
    /// `source`.
    ///
    /// **Not "the nearest declaration above".** That was the first reading, and
    /// it was wrong on the very file the keychain-port guard was written for:
    /// `DuplicatesViewModel` declares a nested `enum Phase` above its own `init`,
    /// so the nearest declaration above that init is `Phase` — the subject was
    /// filed under a type nothing ever constructs, and the rule went quietly
    /// green over the three call sites it existed for. A brace stack is the only
    /// reading that survives nesting, and nesting is the normal shape here.
    public static func typeBodies(in source: String) -> [Body] {
        bodies(in: source, after: ["class", "struct", "actor", "enum", "extension", "protocol"])
    }

    /// Every `func` body in `source`, by the function's own name. `init` bodies
    /// come back under the name `init`.
    public static func functionBodies(in source: String) -> [Body] {
        bodies(in: source, after: ["func", "init"])
    }

    /// The innermost body around `offset`, which is the one that owns it.
    public static func innermost(_ bodies: [Body], around offset: Int) -> Body? {
        bodies.filter { $0.contains(offset) }.min { $0.width < $1.width }
    }

    /// The text of the first body named `name`, or nothing.
    ///
    /// «First», not «the one», and deliberately: an overloaded name has more than
    /// one, and a caller that cares asks `functionBodies` and picks. A caller that
    /// does not is asking about a name it believes is unique, and
    /// `bodiesNamed(_:in:)` is what proves that belief.
    public static func body(of name: String, in source: String) -> String? {
        bodiesNamed(name, in: source).first
    }

    /// The text of every body declared under `name`.
    public static func bodiesNamed(_ name: String, in source: String) -> [String] {
        let characters = Array(source)
        return functionBodies(in: source).filter { $0.name == name }
            .map { String(characters[($0.open + 1)..<$0.close]) }
    }

    /// What a completed word does to the reading: introduce a declaration, name
    /// one that was introduced, or nothing.
    ///
    /// Its own function because the walk below is otherwise one loop carrying
    /// every decision in this file, and a reader that has to hold all of them at
    /// once is how the nested-`enum` misreading survived review.
    private static func introduced(_ word: String, _ keywords: Set<String>,
                                   _ pending: String?, _ expectingName: Bool)
    -> (pending: String?, expectingName: Bool) {
        guard !word.isEmpty else { return (pending, expectingName) }
        // `init` is its own name rather than a keyword a name follows.
        if word == "init", keywords.contains("init") { return ("init", false) }
        if keywords.contains(word) { return (pending, true) }
        if expectingName { return (word, false) }
        return (pending, expectingName)
    }

    /// The brace-matched bodies of every declaration introduced by one of
    /// `keywords`.
    private static func bodies(in source: String, after keywords: Set<String>) -> [Body] {
        var out: [Body] = []
        var stack: [(name: String?, open: Int)] = []
        var pending: String?
        var expectingName = false
        var word = ""
        /// Depth inside a parameter list. Without it, `init(trashing: … = { … })`
        /// hands the declaration's name to the closure and the real body comes
        /// back anonymous — which is `DuplicatesEngine.init` and
        /// `ActionRecord.of`, two of the declarations these scans are about.
        var parens = 0
        func endWord() {
            defer { word = "" }
            (pending, expectingName) = introduced(word, keywords, pending, expectingName)
        }
        for (offset, character) in source.enumerated() {
            if character.isLetter || character.isNumber || character == "_" {
                word.append(character)
                continue
            }
            endWord()
            switch character {
            case "(":
                parens += 1
            case ")":
                parens = max(0, parens - 1)
            case "{":
                // A brace inside a parameter list opens a default value, never
                // the declaration being read.
                stack.append((parens == 0 ? pending : nil, offset))
                if parens == 0 { (pending, expectingName) = (nil, false) }
            case "}":
                let closed = stack.popLast().flatMap { frame in
                    frame.name.map { Body(name: $0, open: frame.open, close: offset) }
                }
                if let closed { out.append(closed) }
            // A declaration that never opened a body — a protocol requirement, a
            // `case` on the way to one — must not leave its name to be claimed by
            // the next brace, which would be somebody else's.
            case ";":
                pending = nil
            default:
                break
            }
        }
        return out
    }
}
