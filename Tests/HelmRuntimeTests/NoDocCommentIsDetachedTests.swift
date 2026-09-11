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
/// inherited it. `KeyPermissions.swift:26` and `RenamePattern.swift:12` are
/// two real cases this repository has carried; this guard is what stops a
/// third from going unnoticed the same way.
///
/// **Why `uncommented`, not `code`.** `SwiftSource.code` blanks a `\` at the
/// end of an escape together with the `\n` that follows it — right for a scan
/// that only ever counts punctuation, and wrong here, because 1,379 lines in
/// `Tests` end in a bare `\` inside a raw string, and dropping their newline
/// drifts every line number after them. `uncommented` keeps every newline
/// where it was; a per-file line-count check against `RepoSource.lines(of:)`
/// is the proof that held for all 1,544 files this was measured against.
///
/// **Why both trees.** The compiler and Quick Help treat `Sources` and
/// `Tests` alike, and `Tests` alone carries 6,547 of the 10,899 `///` blocks
/// in the tree — a guard reading only `Sources` would be blind to two-thirds
/// of what it exists to watch. Two floors, one per directory, are what catch
/// a reader that quietly stopped covering one of them: a single combined
/// floor stays green when either half goes empty.
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
        /// Nothing a comment can document: the end of the file, a closing
        /// `}`, or an `#if`/`#elseif`/`#else`/`#endif` line.
        case documentsNothing

        var description: String {
            switch self {
            case .droppedBlankThenDoc: "dropped: blank then doc"
            case .attachedAcrossGapBlankThenCode: "attached across a gap: blank then code"
            case .documentsNothing: "documents nothing: before `}`, `#if`-family or end of file"
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

    /// Whether a masked code line is one of the three things a comment above
    /// it cannot be documenting: a bare closing brace, or an `#if`-family
    /// directive. Read off `masked` rather than `raw`, because `masked` is
    /// what "code" already means for every other line here.
    static func documentsNothing(_ masked: String) -> Bool {
        let trimmed = masked.trimmingCharacters(in: .whitespaces)
        if trimmed == "}" { return true }
        return ["#if", "#elseif", "#else", "#endif"].contains { trimmed.hasPrefix($0) }
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
    /// because a single combined number stays green when either directory's
    /// half of the walk quietly stops running.
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
}
