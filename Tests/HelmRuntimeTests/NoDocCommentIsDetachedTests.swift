import HelmTestSupport
import XCTest

/// Every `///` block in `Sources` and `Tests` documents something that is
/// still there to read it.
///
/// **Why this is a test.** A doc comment separated from its subject by one
/// blank line is not a warning, it is silence: the compiler either drops the
/// upper block outright (doc, blank, doc) or reattaches it to whatever ended
/// up underneath once its own subject moved away (doc, blank, code) — nothing
/// on screen says which happened, because Quick Help simply shows nothing for
/// the thing that lost its comment and the wrong thing for the one that
/// inherited it. `KeyPermissions.swift`'s note on why its mode check needed
/// no bit-masking, and `RenamePattern.swift`'s legend for its `{name}`,
/// `{date}` and `{counter}` tokens, are two real cases this repository has
/// carried — each a block a blank line dropped in favour of the doc block
/// that followed it; this guard is what stops a third from going unnoticed
/// the same way.
///
/// **Why `uncommented`, not `code`.** `SwiftSource.code` blanks the *inside*
/// of every string literal along with a comment, so a `///`-looking line
/// that only ever sits inside a literal reads back masked as empty and
/// `classify` takes the blank for a doc line; `uncommented` keeps a
/// literal's body instead, which is why `LineKind.code` documents itself as
/// also true of such a line. `code` once drifted the line count
/// too — a `\` line continuation inside an ordinary `"""` literal dropped
/// its own newline along with itself whenever the text was not kept — but
/// that was a defect in `skip(to:escaping:keeping:)`, since fixed, and it was
/// never the reason this guard reaches for `uncommented`: the literal-body
/// difference above is, on its own, both necessary and enough —
/// `testUsingCodeInsteadOfUncommentedFindsAFalseDetachment` below is what
/// pins "necessary", since the existing trap fixture returns `[]` under
/// either mask and so cannot show the difference alone; that test's source
/// reads clean under `uncommented` and finds a false
/// `attachedAcrossGapBlankThenCode` under `code`. A per-file line-count
/// check against `RepoSource.lines(of:)` is the proof for `uncommented`,
/// run over every file `find Sources Tests -name '*.swift' | wc -l` counts;
/// `CodeKeepsAsManyLinesAsTheFileTests` is the same proof for `code`, now
/// that it holds too.
///
/// **Why both trees.** The compiler and Quick Help treat `Sources` and
/// `Tests` alike, so a guard reading only `Sources` is blind to every block
/// in `Tests`; `command grep -rhc '^ *///' Sources | paste -sd+ - | bc` and the
/// same over `Tests` count the `///` lines each holds. Two floors, one per
/// directory, in `testTheCanaryWalksBothTreesInFull`, are what catch a reader
/// that quietly stopped covering most of one of them: a single floor over the
/// sum lets either half lose a large share of its blocks while the total still
/// clears it.
///
/// **What a block is.** Consecutive `///` lines, plus any run of ordinary
/// comment lines between two `///` runs that has no blank line in it — the
/// compiler merges those, so splitting them here would invent a boundary
/// nobody sees. **What "detached" means** is in `DetachedShape` below.
final class NoDocCommentIsDetachedTests: XCTestCase {

    // MARK: - The classifier — a pure function, exercised directly by the fixture test below

    /// What one line is, once comments are blanked but string bodies are kept.
    enum LineKind: Equatable {
        /// Nothing there — trimmed, the raw line is empty.
        case blank
        /// Something the compiler reads as code — non-empty once masked,
        /// which is also true of a `///`-looking line that sits inside a
        /// string literal, since `uncommented` keeps a literal's body.
        case code
        /// Empty once masked, and the raw line starts with `///`.
        case doc
        /// Empty once masked, and not a doc line — `//`, or a line inside a
        /// `/* */` block.
        case comment
    }

    /// The shape of a detachment, named for the failure message: each one is
    /// a judgement a person makes, not a fix this guard applies.
    enum DetachedShape: Equatable {
        /// Blank, then — past any further blanks and comments — another doc
        /// block. The compiler drops the upper block on the floor.
        case droppedBlankThenDoc
        /// Blank, then code. The compiler attaches the block to whatever is
        /// there, which is not what sat directly below it when the comment
        /// was written — included even though the compiler does attach it,
        /// because the fix is one blank line and the block is talking about
        /// the wrong thing until somebody removes it.
        case attachedAcrossGapBlankThenCode
        /// Nothing a comment can document: the end of the file, a line
        /// beginning with a closing `}`, `)` or `]`, a switch's catch-all
        /// arm written on one line, in one of four spellings — `default:`,
        /// `default :` (any run of spaces or tabs before the colon),
        /// `@unknown default:` or `@unknown case _:` — or an
        /// `#if`/`#elseif`/`#else`/`#endif` line. A spelling split across
        /// lines — `@unknown` on one line and `default:` on the next, or
        /// `default` and `:` on separate lines — is not recognised.
        case documentsNothing

        var description: String {
            switch self {
            case .droppedBlankThenDoc: "dropped: blank then doc"
            case .attachedAcrossGapBlankThenCode: "attached across a gap: blank then code"
            case .documentsNothing: "documents nothing: before a closing `}`/`)`/`]`, a catch-all arm (`default:`, `default :`, `@unknown default:`, `@unknown case _:`), `#if`-family or end of file"
            }
        }
    }

    /// A found block, named by the line its first `///` sits on — 1-based,
    /// because that is what a person opens a file to.
    struct DetachedBlock: Equatable {
        let startLine: Int
        let shape: DetachedShape
    }

    /// `raw` is blank when trimmed; otherwise `code` when `masked` is not
    /// also blank; otherwise `doc` when the raw line starts with `///`;
    /// otherwise `comment`. In that order, because a blank `///` inside a
    /// kept string is code before it is ever asked whether it looks like a
    /// doc line.
    static func classify(raw: String, masked: String) -> LineKind {
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return .blank }
        guard masked.trimmingCharacters(in: .whitespaces).isEmpty else { return .code }
        return raw.trimmingCharacters(in: .whitespaces).hasPrefix("///") ? .doc : .comment
    }

    /// Whether a masked code line is one of the things a comment above it
    /// cannot be documenting: a line beginning with a closing `}`, `)` or
    /// `]` — `})`, `},`, `} else {`, `]` and `)` all qualify, because each
    /// continues the statement that just closed rather than opening a
    /// subject of its own — a switch's catch-all arm, spelled `default:`,
    /// `default :` (any run of spaces or tabs before the colon), `@unknown
    /// default:` or `@unknown case _:`, or an `#if`-family directive. Not plain `case`: an
    /// enum case is a declaration and its `///` attaches to it, which
    /// `swiftc -emit-symbol-graph` shows as a `docComment` on the case and
    /// shows nowhere at all for a comment above any of those four catch-all
    /// spellings, since a switch arm is a statement rather than a symbol.
    /// Read off `masked` rather than `raw`, because `masked` is what "code"
    /// already means for every other line here.
    static func documentsNothing(_ masked: String) -> Bool {
        let trimmed = masked.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("}") || trimmed.hasPrefix(")") || trimmed.hasPrefix("]") { return true }
        if isDefaultArm(trimmed) { return true }
        return ["#if", "#elseif", "#else", "#endif"].contains { trimmed.hasPrefix($0) }
    }

    /// Whether `trimmed` opens a switch's catch-all arm — `default:`,
    /// `default :`, `@unknown default:` or `@unknown case _:` — and not an
    /// identifier that merely begins with `default`, such as
    /// `defaultValue = 1` or `default_x`: only whitespace may sit between
    /// `default` and the colon that follows it, and `@unknown case` only
    /// qualifies when the pattern it introduces is the bare `_`.
    static func isDefaultArm(_ trimmed: String) -> Bool {
        var rest = trimmed
        if rest.hasPrefix("@unknown") {
            rest = rest.dropFirst("@unknown".count).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("case") {
                let afterCase = rest.dropFirst("case".count).trimmingCharacters(in: .whitespaces)
                guard afterCase.hasPrefix("_") else { return false }
                return afterCase.dropFirst().trimmingCharacters(in: .whitespaces).hasPrefix(":")
            }
        }
        guard rest.hasPrefix("default") else { return false }
        return rest.dropFirst("default".count).trimmingCharacters(in: .whitespaces).hasPrefix(":")
    }

    static func lineKinds(raw: [String], masked: [String]) -> [LineKind] {
        zip(raw, masked).map(classify)
    }

    /// Every merged `///` run in `kinds`, as a half-open range — merged the
    /// way the compiler merges: a run of comment lines with no blank in it,
    /// sitting between two `///` runs, does not split them.
    static func blockRanges(_ kinds: [LineKind]) -> [(start: Int, end: Int)] {
        var out: [(start: Int, end: Int)] = []
        var index = 0
        let count = kinds.count
        while index < count {
            guard kinds[index] == .doc else { index += 1; continue }
            let start = index
            var end = index
            extending: while true {
                while end < count, kinds[end] == .doc { end += 1 }
                var probe = end
                while probe < count, kinds[probe] == .comment { probe += 1 }
                guard probe < count, kinds[probe] == .doc else { break extending }
                end = probe
            }
            out.append((start, end))
            index = end
        }
        return out
    }

    /// Every block in `kinds` that is detached from a subject, by the rule
    /// above `DetachedShape`.
    static func detachedBlocks(raw: [String], masked: [String]) -> [DetachedBlock] {
        let kinds = lineKinds(raw: raw, masked: masked)
        let count = kinds.count
        var out: [DetachedBlock] = []
        for (start, end) in blockRanges(kinds) {
            var after = end
            while after < count, kinds[after] == .comment { after += 1 }
            let shape: DetachedShape?
            if after >= count {
                shape = .documentsNothing
            } else if kinds[after] == .blank {
                var past = after
                while past < count, kinds[past] == .blank || kinds[past] == .comment { past += 1 }
                if past >= count {
                    shape = .documentsNothing
                } else if kinds[past] == .doc {
                    shape = .droppedBlankThenDoc
                } else {
                    shape = documentsNothing(masked[past]) ? .documentsNothing : .attachedAcrossGapBlankThenCode
                }
            } else {
                shape = documentsNothing(masked[after]) ? .documentsNothing : nil
            }
            if let shape { out.append(DetachedBlock(startLine: start + 1, shape: shape)) }
        }
        return out
    }

    // MARK: - The walk

    /// One file, both readings, kept in step.
    private struct Analyzed {
        let file: String
        let raw: [String]
        let masked: [String]
    }

    /// Every `.swift` file under `directory`, read the two ways this guard
    /// needs — and checked, per file, that the two readings agree on how many
    /// lines there are. An unreadable file is not skipped: `RepoSource.lines`
    /// throws, `try` here does not catch it, and the whole test fails naming
    /// the file XCTest was already about to report.
    private func analyze(under directory: String) throws -> [Analyzed] {
        try SwiftSource.uncommented(under: directory).map { read in
            let raw = try RepoSource.lines(of: read.path)
            let masked = read.text.components(separatedBy: "\n")
            XCTAssertEqual(raw.count, masked.count,
                "\(read.path): raw has \(raw.count) line(s), the masked reading has \(masked.count) — "
                + "the two readings drifted apart and every line number below it would be a guess")
            return Analyzed(file: read.path, raw: raw, masked: masked)
        }
    }

    // MARK: - The canary

    /// A guard reading nothing is green over nothing. Two floors and not one,
    /// because a single floor over the sum stays green while either directory's
    /// half of the walk loses a large share of what it reads.
    func testTheCanaryWalksBothTreesInFull() throws {
        let sources = try analyze(under: "Sources")
        XCTAssertGreaterThanOrEqual(sources.count, 400,
            "only \(sources.count) Sources files — the walk found far fewer than the tree has")
        let sourcesBlocks = sources.reduce(0) { $0 + Self.blockRanges(Self.lineKinds(raw: $1.raw, masked: $1.masked)).count }
        XCTAssertGreaterThanOrEqual(sourcesBlocks, 3500,
            "only \(sourcesBlocks) /// blocks in Sources — the classifier is finding far fewer than the tree has")

        let tests = try analyze(under: "Tests")
        XCTAssertGreaterThanOrEqual(tests.count, 800,
            "only \(tests.count) Tests files — the walk found far fewer than the tree has")
        let testsBlocks = tests.reduce(0) { $0 + Self.blockRanges(Self.lineKinds(raw: $1.raw, masked: $1.masked)).count }
        XCTAssertGreaterThanOrEqual(testsBlocks, 5000,
            "only \(testsBlocks) /// blocks in Tests — the classifier is finding far fewer than the tree has")
    }

    // MARK: - The guard

    func testNoDocCommentIsDetachedFromItsSubject() throws {
        let files = try analyze(under: "Sources") + analyze(under: "Tests")
        let hits = files.flatMap { file in
            Self.detachedBlocks(raw: file.raw, masked: file.masked).map { (file: file.file, block: $0) }
        }
        XCTAssertTrue(hits.isEmpty, """
            \(hits.count) doc comment(s) sit detached from what they document — Quick Help shows \
            nothing for the declaration that lost its comment, and the compiler has either dropped \
            the block or handed it to whatever ended up underneath once its own subject moved away:
            \(hits.map { "\($0.file):\($0.block.startLine) — \($0.block.shape.description)" }.joined(separator: "\n"))
            Each is a judgement for a person — attach it, turn it into a plain comment, or delete it \
            — and is not fixed by widening this test.
            """)
    }

    // MARK: - The fixture — every shape the classifier must find, and every one it must not

    /// `source`'s detached-block shapes, read the same way the walk reads a
    /// real file: `SwiftSource.uncommented` for the mask, a plain split for
    /// the raw lines.
    private func shapes(in source: String) -> [NoDocCommentIsDetachedTests.DetachedShape] {
        let masked = SwiftSource.uncommented(source).components(separatedBy: "\n")
        let raw = source.components(separatedBy: "\n")
        XCTAssertEqual(raw.count, masked.count, "the fixture itself drifted lines — «\(source)»")
        return Self.detachedBlocks(raw: raw, masked: masked).map(\.shape)
    }

    func testDroppedBlankThenDocIsFound() {
        XCTAssertEqual(shapes(in: """
            /// First.
            /// still first.

            /// Second, and this one is attached below.
            enum E {}
            """), [.droppedBlankThenDoc])
    }

    func testAttachedAcrossAGapBlankThenCodeIsFound() {
        XCTAssertEqual(shapes(in: """
            /// Explains a value that used to be right underneath.

            let value = 1
            """), [.attachedAcrossGapBlankThenCode])
    }

    func testDocumentsNothingBeforeAClosingBraceIsFound() {
        XCTAssertEqual(shapes(in: """
            struct S {
                /// Dangling — the property this described is gone.
            }
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeAnIfDirectiveIsFound() {
        XCTAssertEqual(shapes(in: """
            /// Guards the debug build.
            #if DEBUG
            let value = 1
            #endif
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeAClosingParenAndBraceIsFound() {
        XCTAssertEqual(shapes(in: """
            run({
                work()
                /// dangling at the end of a closure argument
            })
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeAClosingBraceAndCommaIsFound() {
        XCTAssertEqual(shapes(in: """
            let items = [
                Item {
                    /// dangling
                },
            ]
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeAClosingBraceElseIsFound() {
        XCTAssertEqual(shapes(in: """
            func run() {
                if a {
                    x()
                    /// dangling before else
                } else {
                    y()
                }
            }
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeAClosingBracketIsFound() {
        XCTAssertEqual(shapes(in: """
            let xs = [
                1,
                /// dangling in an array literal
            ]
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeAClosingParenIsFound() {
        XCTAssertEqual(shapes(in: """
            let v = call(
                1
                /// dangling in an argument list
            )
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeADefaultArmIsFound() {
        XCTAssertEqual(shapes(in: """
            switch v {
            case 1: break
            /// documents a switch arm
            default: break
            }
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeADefaultArmWithASpaceBeforeTheColonIsFound() {
        XCTAssertEqual(shapes(in: """
            switch v {
            case 1: break
            /// documents a switch arm
            default : break
            }
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeADefaultArmWithASpaceBeforeTheColonAfterABlankLineIsFound() {
        XCTAssertEqual(shapes(in: """
            switch v {
            case 1: break
            /// documents a switch arm

            default : break
            }
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeAnUnknownDefaultArmIsFound() {
        XCTAssertEqual(shapes(in: """
            switch v {
            case .a: break
            /// documents a switch arm
            @unknown default: break
            }
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeAnUnknownDefaultArmAfterABlankLineIsFound() {
        XCTAssertEqual(shapes(in: """
            switch v {
            case .a: break
            /// documents a switch arm

            @unknown default: break
            }
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeAnUnknownCaseUnderscoreArmIsFound() {
        XCTAssertEqual(shapes(in: """
            switch v {
            case .a: break
            /// documents a switch arm
            @unknown case _: break
            }
            """), [.documentsNothing])
    }

    func testDocumentsNothingBeforeAnUnknownCaseUnderscoreArmAfterABlankLineIsFound() {
        XCTAssertEqual(shapes(in: """
            switch v {
            case .a: break
            /// documents a switch arm

            @unknown case _: break
            }
            """), [.documentsNothing])
    }

    /// A `case` is a declaration and its `///` attaches to it rather than
    /// documenting nothing — `swiftc -emit-symbol-graph` records a
    /// `docComment` on the case and nothing at all for a comment above a
    /// switch's `default:`, which is a statement rather than a symbol.
    func testABlockAboveAnEnumCaseIsNotFound() {
        XCTAssertEqual(shapes(in: """
            enum E {
                /// Explains foo.
                case foo
            }
            """), [])
    }

    /// An identifier merely beginning with `default` is not a `default` arm
    /// — the block above it documents that identifier and is attached, the
    /// same as any other declaration.
    func testABlockAboveAnIdentifierMerelyBeginningWithDefaultIsNotFound() {
        XCTAssertEqual(shapes(in: """
            /// doc
            defaultValue = 1
            """), [])
    }

    /// The same identifier, now past a blank line: still attached across
    /// the gap, not read as a `default` arm that documents nothing.
    func testABlockAboveAnIdentifierMerelyBeginningWithDefaultAfterABlankLineIsFound() {
        XCTAssertEqual(shapes(in: """
            /// doc

            defaultValue = 1
            """), [.attachedAcrossGapBlankThenCode])
    }

    func testDocumentsNothingAtEndOfFileIsFound() {
        // A trailing blank line before the closing `"""` is not decoration: it
        // gives the fixture's own text a final newline, the way every real
        // file on disk has one — without it, `SwiftSource.uncommented` still
        // appends the newline a trailing `///` line would otherwise have had,
        // and the fixture's raw and masked readings drift by that one line.
        XCTAssertEqual(shapes(in: """
            let value = 1

            /// Trailing, and nothing ever follows it.

            """), [.documentsNothing])
    }

    /// An attribute is code, not a comment — a block above one is attached.
    func testABlockAboveAnAttributeIsNotFound() {
        XCTAssertEqual(shapes(in: """
            /// Explains the flag.
            @MainActor
            func run() {}
            """), [])
    }

    /// An ordinary `//` with no blank line is a connector, not a gap — the
    /// compiler attaches straight through it.
    func testABlockAboveAPlainCommentWithNoBlankLineIsNotFound() {
        XCTAssertEqual(shapes(in: """
            /// Explains this function.
            // an implementation detail, not part of the doc
            func run() {}
            """), [])
    }

    /// **The trap.** A raw line that starts with `///` is not a doc line when
    /// it sits inside a string literal — `uncommented` keeps its body, so the
    /// mask is non-empty there and `classify` reads it as code, same as
    /// `ACommentIsNotAUseOfAKeyTests` had to for the reading this shares.
    func testATripleSlashInsideAStringLiteralIsNotFound() {
        XCTAssertEqual(shapes(in: #"""
            let s = """
            /// not a doc comment
            """
            func run() {}
            """#), [])
    }

    /// Pins the "necessary" half of "Why `uncommented`, not `code`" above:
    /// the trap fixture just above this one returns `[]` under both masks,
    /// so it alone cannot show the difference the doc comment claims. This
    /// source can, because the `///`-looking line sits above a blank rather
    /// than directly above code — `uncommented` keeps its body, `classify`
    /// reads it as code, and the block never forms; `code` blanks that same
    /// body, `classify` reads the blank as a doc line, and the block forms
    /// above a gap that ends in code, which is exactly
    /// `attachedAcrossGapBlankThenCode`.
    func testUsingCodeInsteadOfUncommentedFindsAFalseDetachment() {
        let source = "let s = \"\"\"\n/// not a doc comment\n\n\"\"\"\nlet x = 1\n"
        let raw = source.components(separatedBy: "\n")

        let uncommentedMasked = SwiftSource.uncommented(source).components(separatedBy: "\n")
        XCTAssertEqual(raw.count, uncommentedMasked.count, "the fixture itself drifted lines — «\(source)»")
        XCTAssertEqual(Self.detachedBlocks(raw: raw, masked: uncommentedMasked).map(\.shape), [],
            "uncommented must read the `///`-looking line inside the literal as code, not doc")

        let codeMasked = SwiftSource.code(source).components(separatedBy: "\n")
        XCTAssertEqual(raw.count, codeMasked.count, "the fixture itself drifted lines — «\(source)»")
        XCTAssertEqual(Self.detachedBlocks(raw: raw, masked: codeMasked).map(\.shape),
            [.attachedAcrossGapBlankThenCode],
            "code blanks the literal's body, so the same line reads back as a dropped doc line — "
            + "this false positive is what `uncommented` exists to avoid")
    }
}
