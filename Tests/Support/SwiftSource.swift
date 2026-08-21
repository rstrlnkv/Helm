import Foundation
import HelmRuntime

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
        read(source, keepingStrings: false)
    }

    /// `source` with comments blanked and the insides of string literals **kept**
    /// — the other half of the same walk, for a scan whose subject is a literal.
    ///
    /// **`code` is the wrong reading for one family of check and it is not
    /// obviously wrong.** The orphan-translation scan asks whether anything in
    /// the tree still says `L("Off")`; run over `code` output that line reads
    /// `L("")` and all 1054 keys report as dead at once, which at least fails
    /// loudly. Run over the **raw** file it reads the opposite way and fails
    /// silently: this repository writes backticked names inside doc comments on
    /// purpose — `DocumentsNameTheTreeTests` exists to read them back — so
    /// `Sources/HelmApp/AppStrings.swift`'s «Not `L("Off")`» keeps the key «Off»
    /// alive by explaining why nothing uses it there.
    ///
    /// Not a second walk, and it could not be one: a `//` inside a string is not
    /// a comment, so blanking comments correctly already requires parsing every
    /// literal. It is the same parse with the copying turned back on.
    ///
    /// Escapes come back **as written**: `\"` stays `\"`. A caller that decodes
    /// them does it afterwards, because decoding first would end a literal at
    /// the first escaped quote.
    public static func uncommented(_ source: String) -> String {
        read(source, keepingStrings: true)
    }

    /// The delimiters, hoisted. They were `Array("…")` literals inside the loop
    /// — seven of them built at **every character position**, beside a `String`
    /// allocated per character by `take(1)`, and that is where the whole cost
    /// was. Measured over every file of `Sources/` on 2026-08-21, three readings
    /// each: **3.728 / 3.734 / 3.743 s before, 0.557 / 0.559 / 0.558 s after**,
    /// with the output byte-identical on every file of `Sources/` and `Tests/`
    /// and on the corpus of unterminated literals, raw blocks, CRLF and emoji
    /// that `ACommentIsNotAUseOfAKeyTests` keeps. Worth having because XCTest
    /// builds an instance per test case, so a class of ten whole-tree scans paid
    /// the old cost ten times.
    private static let lineComment: [Character] = ["/", "/"]
    private static let blockOpen: [Character] = ["/", "*"]
    private static let blockClose: [Character] = ["*", "/"]
    private static let rawBlockOpen: [Character] = ["#", "\"", "\"", "\""]
    private static let rawBlockClose: [Character] = ["\"", "\"", "\"", "#"]
    private static let rawOpen: [Character] = ["#", "\""]
    private static let rawClose: [Character] = ["\"", "#"]
    private static let block: [Character] = ["\"", "\"", "\""]
    private static let quote: [Character] = ["\""]
    private static let newline: [Character] = ["\n"]

    /// The three characters any delimiter above can begin with. Ordinary code
    /// is none of them, so one comparison sends the common character straight
    /// through instead of putting it past six pattern matches.
    private static func opensADelimiter(_ character: Character) -> Bool {
        character == "/" || character == "\"" || character == "#"
    }

    /// One walk, two readings: comments always go, literals go or stay.
    ///
    /// Written against an index into `[Character]` rather than a consuming
    /// slice, so that recognising a delimiter compares characters in place
    /// instead of building an array to compare against — and accumulating into
    /// `[Character]`, which appends without re-encoding, rather than into a
    /// `String` grown one grapheme at a time.
    private static func read(_ source: String, keepingStrings: Bool) -> String {
        let characters = Array(source)
        let count = characters.count
        var out: [Character] = []
        out.reserveCapacity(count)
        var index = 0

        /// Whether `characters` reads `pattern` at `index`.
        func matches(_ pattern: [Character]) -> Bool {
            guard index + pattern.count <= count else { return false }
            for offset in 0..<pattern.count where characters[index + offset] != pattern[offset] {
                return false
            }
            return true
        }
        /// The next `width` characters, copied or dropped.
        func delimiter(_ width: Int, keeping: Bool) {
            if keeping { for offset in 0..<width where index + offset < count {
                out.append(characters[index + offset])
            } }
            index += width
        }
        /// Everything up to and including `close`. Kept verbatim, or blanked
        /// but for its newlines — which stay so a finding can still name a line.
        func skip(to close: [Character], escaping: Bool, keeping: Bool) {
            while index < count {
                if escaping, characters[index] == "\\" {
                    delimiter(2, keeping: keeping)
                    continue
                }
                if matches(close) {
                    delimiter(close.count, keeping: keeping)
                    return
                }
                if keeping { out.append(characters[index]) }
                else if characters[index] == "\n" { out.append("\n") }
                index += 1
            }
        }

        while index < count {
            let head = characters[index]
            guard opensADelimiter(head) else {
                out.append(head)
                index += 1
                continue
            }
            if matches(lineComment) {
                skip(to: newline, escaping: false, keeping: false)
                out.append("\n")
            } else if matches(blockOpen) {
                index += 2
                skip(to: blockClose, escaping: false, keeping: false)
            } else if matches(rawBlockOpen) {
                delimiter(4, keeping: keepingStrings)
                skip(to: rawBlockClose, escaping: false, keeping: keepingStrings)
            } else if matches(rawOpen) {
                delimiter(2, keeping: keepingStrings)
                skip(to: rawClose, escaping: false, keeping: keepingStrings)
            } else if matches(block) {
                delimiter(3, keeping: keepingStrings)
                skip(to: block, escaping: true, keeping: keepingStrings)
            } else if head == "\"" {
                delimiter(1, keeping: keepingStrings)
                skip(to: quote, escaping: true, keeping: keepingStrings)
            } else {
                out.append(head)
                index += 1
            }
        }
        return String(out)
    }

    // MARK: - The whole of a directory, read once a process

    /// One file of the repository and the reading of it that was asked for.
    public struct Read: Sendable, Equatable {
        /// Repo-relative, because that is what a finding has to name.
        public let path: String
        public let text: String
    }

    /// Every `.swift` file under a repository directory, read as `code(_:)`
    /// reads one — **walked, loaded and parsed once a process**, however many
    /// test cases ask for it.
    ///
    /// **XCTest builds an instance per test case.** An instance method that
    /// reads the tree therefore reads it once per *case*, not once per class,
    /// and three whole-tree scans in a twelve-case class is thirty-six walks.
    /// Measured on 2026-08-21, the two classes that did this cost 11.1 s and
    /// 14.9 s of a suite whose other hundred-odd classes are milliseconds.
    ///
    /// The tree does not change while the suite runs, so the answer is the same
    /// every time and the second walk buys nothing. `TheTreeIsReadOnceAProcessTests`
    /// is the promise: it counts the files taken off disk and asks the reader
    /// twice.
    public static func code(under directory: String) throws -> [Read] {
        try files(under: directory, keepingStrings: false)
    }

    /// The same, read as `uncommented(_:)` reads one — comments blanked,
    /// literals kept.
    ///
    /// **Cached apart from `code(under:)` and not merely alongside it.** One
    /// cache keyed on the directory would serve whichever caller came second
    /// the first one's text, and that failure is silent in the direction that
    /// matters: every `L("Off")` in the tree arrives as `L("")` and the orphan
    /// scan condemns all thousand-odd keys at once.
    public static func uncommented(under directory: String) throws -> [Read] {
        try files(under: directory, keepingStrings: true)
    }

    /// How many files the two readers above have taken off disk in this
    /// process.
    ///
    /// A counter is the only way to write «and not again» down as an assertion.
    /// Timing it would be a test of this Mac's mood, and comparing the two
    /// answers proves only that the reader is a function.
    public static var filesRead: Int { counter.value }

    /// **`LockedMemo` rather than a fifth hand-rolled one.** It is `HelmRuntime`'s,
    /// it is one lock and one dictionary with the build under the lock, and its
    /// own documentation is the account of the four copies that existed before
    /// it — three of them under one name and already not the same thing. This
    /// was written as a sixth before that was noticed.
    ///
    /// The value is a `Result` so the throwing read fits a non-throwing memo,
    /// and a failure is remembered on purpose: the subject is a fixed tree, so
    /// a directory that could not be read once cannot be read now either, and
    /// re-asking would only walk it again to fail again.
    private static let tree = LockedMemo<String, Result<[Read], any Error>>()

    private static func files(under directory: String, keepingStrings: Bool) throws -> [Read] {
        // The reading is half the key. A directory read both ways is two
        // answers, and they are not interchangeable.
        let key = (keepingStrings ? "kept:" : "code:") + directory
        return try tree.value(for: key) {
            Result {
                let read = try RepoSource.swiftFiles(under: directory).map {
                    Read(path: $0, text: self.read(try RepoSource.text(of: $0),
                                                   keepingStrings: keepingStrings))
                }
                counter.add(read.count)
                return read
            }
        }.get()
    }

    private static let counter = Counter()

    /// An accumulator, which is why it is not `ProgressBox` next door: that one
    /// records the *last* value a progress callback reported, and this adds.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var total = 0

        func add(_ n: Int) {
            lock.lock()
            total += n
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return total
        }
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
        // **A fast no, before the copy.** The walk below needs the whole source
        // as `[Character]` before it can look at anything, and a call site *is*
        // an occurrence of `callee(` — so a source without that substring has
        // none, exactly rather than probably
        // (`testAFileThatNeverSpellsTheTypeHoldsNoConstructionOfIt`).
        //
        // It belongs here and not at a caller: every scan that asks about
        // several callees over one tree was paying a copy per callee, and
        // `PortsAtConstruction` — three subjects over all of `Tests/` — made
        // three of every file for answers two of them could not hold. Measured
        // 2026-08-21, that scan went 2.421 s to 0.200 s.
        guard source.contains(callee + "(") else { return [] }
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
