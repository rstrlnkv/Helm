import HelmTestSupport
import XCTest
@testable import HelmUI

/// **A paragraph is a paragraph wherever it is written; a caption is not.**
///
/// Keep Awake's lid row carried 606 characters of German under one switch —
/// seven drawn lines, 3.5× the next-longest caption on its page — and nothing in
/// the tree could see it. The repair is `HelmExplainer`: the row keeps what the
/// decision needs and the ⓘ beside its name opens the rest. This is the half
/// that stops the next one being written, and it is a **ratchet** rather than a
/// gate, for the reason the type and space ladders are: the number is what the
/// tree measured on the day it landed, and only the commit that lowers it lowers
/// it.
///
/// **The ceiling is measured, not chosen.** 200 characters is the longest
/// caption the Keep Awake settings page draws besides the one that started this
/// — `lidRefused`, 188 in German — with a translator's headroom on top. Nothing
/// in the app *needs* to be shorter than the longest thing it already says; what
/// this counts is how many pieces of copy are longer, so that a fifth is a
/// decision somebody takes rather than a line somebody adds.
///
/// **What it can see.** Every `L("…")` in a file that draws: the design system,
/// every module's UI, the app shell. Two exclusions, both by shape rather than
/// by name:
///
/// - `ChangelogData.swift`. What's New is a page of paragraphs and length there
///   is the point — every one of the twenty-five longest strings in the app is
///   one of its entries.
/// - Anything written `.text(L("…"))`, which is a `HelmExplainer.Block`. That is
///   the place a long explanation is *supposed* to go, and counting it would
///   make the guard punish the repair it exists to encourage.
///
/// **What it cannot see, said plainly rather than left to be discovered.** It
/// reads literals, so a caption *composed* at the call site is invisible to it:
/// `LayoutSettingsPage.tapKeyNote` joins `tapKeyHint` with one of three further
/// keys and reaches **554 characters in German** — the second case of exactly
/// this defect, found by measuring rather than by reading, and left for its own
/// change. Two of the four counted below are its halves. A strict form of this
/// rule — «a caption over the ceiling has an explainer beside it» — needs the
/// drawn string rather than the literal, which means asking `HelmSettingRow`
/// itself at render time; that is the shape to reach for once the composed cases
/// are down, and it would fail today for a reason that is not this commit's.
final class CopyTooLongForARowIsCountedTests: XCTestCase {

    /// 188 is `lidRefused` in German, the longest caption its page draws.
    private static let ceiling = 200

    /// **4**, measured 2026-08-21 against this commit, down from 5 — the fifth
    /// was the lid row this rule was written for. Every one of the four carries
    /// its reason:
    ///
    /// - `LayoutStrings.tapKeyHint` (266 ru) and `.globeNote` (220 fr) are two
    ///   halves of one settings-row caption and are the next case for
    ///   `HelmExplainer`; joined, they are longer than the one just repaired.
    /// - `AppStrings`' reset warning (281 de) is the body of a confirmation
    ///   dialog, which is a place a paragraph belongs.
    /// - `AutopilotStrings`' opening sentence (237 fr) is a module's own
    ///   description on the page that introduces it, not a line under a control.
    ///
    /// Two of the four are the rule's next job and two are copy in a role that
    /// carries length. The number does not distinguish them, and nothing here
    /// should: a role is an argument, and an argument belongs in the commit that
    /// lowers this.
    private static let recorded = 4

    private struct Offence {
        let file: String
        let line: Int
        let language: AppLanguage
        let length: Int
        let key: String
    }

    // MARK: - The scan

    /// A file and its text, so a fixture can go through the very same walk the
    /// tree does — `SwiftSource.Read`'s own initializer is internal to the
    /// support target.
    private typealias Source = (path: String, text: String)

    /// Every `L("…")` a drawn file spells, with the explainer's own blocks left
    /// out — as `(file, line, key)`.
    ///
    /// `SwiftSource.uncommented` rather than the raw text: this repository
    /// explains every rule in a comment that quotes the thing it forbids, and
    /// this file is itself an example — a scan that read comments would report
    /// the explanation as the offence.
    ///
    /// A line at a time, and that is exact rather than convenient: a key is one
    /// literal on one line however long it runs, because `NoOrphanTranslations`
    /// looks for `"<the whole key>"` in the source and a key split over a `+` is
    /// a key nothing in the tree asks for. A literal holding an escaped quote is
    /// skipped — the `")` this reads for would end in the wrong place — and the
    /// floor in `testTheScanStillHasCopyToJudge` is what says the skipping has
    /// not quietly become the rule.
    /// One key where it is written.
    private struct Spelling {
        let file: String
        let line: Int
        let key: String
    }

    private func keys(in reads: [Source]) -> [Spelling] {
        var out: [Spelling] = []
        for read in reads where !read.path.hasSuffix("ChangelogData.swift") {
            for (index, line) in read.text.components(separatedBy: "\n").enumerated() {
                var searched = line[...]
                while let start = searched.range(of: "L(\"") {
                    let after = start.upperBound
                    guard let close = searched[after...].range(of: "\")") else { break }
                    let key = String(searched[after..<close.lowerBound])
                    // A block of an explanation, which is where length is meant
                    // to go. Read off the three characters in front of the call
                    // rather than off the whole line: a line can hold both.
                    let before = searched[..<start.lowerBound]
                    if !before.hasSuffix(".text(") && !key.contains("\"") {
                        out.append(Spelling(file: read.path, line: index + 1, key: key))
                    }
                    searched = searched[close.upperBound...]
                }
            }
        }
        return out
    }

    private func offences(in reads: [Source]) -> [Offence] {
        var out: [Offence] = []
        for found in keys(in: reads) {
            for language in AppLanguage.allCases {
                let drawn = L(found.key, language: language)
                guard drawn.count > Self.ceiling else { continue }
                out.append(Offence(file: found.file, line: found.line, language: language,
                                   length: drawn.count, key: found.key))
            }
        }
        return out
    }

    /// One entry per *string*, in its worst language — a sentence that is long
    /// in six of eight is one piece of copy, not six.
    private func worst(_ offences: [Offence]) -> [Offence] {
        Dictionary(grouping: offences) { "\($0.file):\($0.line)" }
            .values
            .compactMap { $0.max { $0.length < $1.length } }
            .sorted { $0.length > $1.length }
    }

    private func drawnFiles() throws -> [Source] {
        let reads = try SwiftSource.uncommented(under: "Sources/HelmUI")
            + SwiftSource.uncommented(under: "Sources/HelmApp")
            + SwiftSource.uncommented(under: "Sources/Modules").filter {
                $0.path.contains("/UI/")
            }
        return reads.map { (path: $0.path, text: $0.text) }
    }

    // MARK: - The ratchet

    func testNoNewWallOfTextArrives() throws {
        let found = worst(offences(in: try drawnFiles()))
        let listed = found.map {
            "  \($0.file):\($0.line)  \($0.length) (\($0.language.rawValue))  «\($0.key.prefix(60))…»"
        }.joined(separator: "\n")
        XCTAssertLessThanOrEqual(found.count, Self.recorded, """
            \(found.count) pieces of copy are over \(Self.ceiling) characters; the recorded \
            number is \(Self.recorded). A line under a control that runs this long belongs in \
            a `HelmExplainer` behind the ⓘ — see `HelmSettingRow(explainer:)`. This number is \
            only ever lowered, by the commit that lowers it.
            \(listed)
            """)
    }

    /// **A ratchet is satisfied by zero, and zero is what a broken scan finds.**
    ///
    /// Three floors, and the third is the one that matters: a reader that had
    /// stopped decoding keys would hand every literal back as its own English,
    /// which is shorter than every translation and would empty this check
    /// without emptying its file list.
    func testTheScanStillHasCopyToJudge() throws {
        let reads = try drawnFiles()
        XCTAssertGreaterThan(reads.count, 50, "the file list has collapsed")
        let found = keys(in: reads)
        XCTAssertGreaterThan(found.count, 500,
                             "the scan sees \(found.count) strings in the whole app — either the "
                             + "tree really has that few, or it has stopped matching `L(\"…\")`")
        let translated = found.filter { L($0.key, language: .ru) != $0.key }.count
        XCTAssertGreaterThan(translated * 10, found.count * 9, """
            only \(translated) of \(found.count) keys read back differently in Russian, so the \
            lookup is answering with the key rather than the table and every length below is \
            English's
            """)
    }

    /// And that it still sees both halves of the shape it is built on: a long
    /// caption is counted, the same words inside an explainer's block are not.
    func testTheScanSeesTheShape() {
        // Not in any table, so `L()` hands it back and its length is its own.
        let long = String(repeating: "wall of text, ", count: 20)
        let plain: Source = ("Sources/HelmUI/Fixture.swift",
                             "    static var note: String { L(\"\(long)\") }")
        XCTAssertEqual(offences(in: [plain]).isEmpty, false,
                       "the scan no longer sees a long caption at all")

        let explained: Source = ("Sources/HelmUI/Fixture.swift",
                                 "        .text(L(\"\(long)\")),")
        XCTAssertEqual(offences(in: [explained]).count, 0, """
            copy inside an explainer block is being counted, so the guard punishes the very \
            repair it exists to ask for
            """)
    }
}
