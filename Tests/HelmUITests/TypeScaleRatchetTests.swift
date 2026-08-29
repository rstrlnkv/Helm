import HelmTestSupport
import XCTest

/// **Type has one scale: 10 · 11 · 13 · 16 · 22 · 40 pt.**
///
/// The mockups carried seventeen sizes before this scale was chosen, and the
/// finding recorded in `v3/audit.js` is the one that generalises: *there were
/// more differences than were visible*. A 15 pt heading beside a 16 pt heading
/// is not a decision anybody took; it is two people, or one person twice.
///
/// A ratchet like the space ladder beside it: the number is what the tree
/// measured on the day it landed, and only the commit that lowers it lowers it.
///
/// **Two units, because a size can be typed or it can be named.** The first
/// ratchet counts a number written by hand — `.system(size: 15)` and the
/// `NSFont` builders. The second counts a *style*: `.font(.callout)`, which is
/// a name for a role and resolves to a size all the same.
///
/// This file used to count only the first, and said why: counting the 29
/// semantic styles «would put a number in this test that nothing can lower
/// until the tokens land». They landed in `a49c09d` — `HelmText.rowTitle`,
/// `.rowDetail`, `.sectionHeading`, `.groupLabel` — so the reason has lapsed
/// and the count is here. The other half of that paragraph still stands and is
/// answered rather than dropped: what macOS resolves a style to is a fact about
/// the OS, so it is **measured** in `testTheStylesStillResolveWhereTheyDid`
/// rather than remembered here. A macOS release that moves `.callout` to 13
/// fails that test instead of quietly leaving these two ratchets guarding
/// nothing.
final class TypeScaleRatchetTests: XCTestCase {

    /// Measured 2026-08-11 against `main` = `8b8c547` at **11**. No single value
    /// dominated — 9, 12, 15, 17, 19, 34 and 44, one or two each, which is what
    /// «more differences than are visible» looks like when it is written down.
    ///
    /// **3** after the sweep of 2026-08-12, and all three are one shape: a
    /// figure sized to a *drawn* thing rather than to a page. `RingView`'s 19
    /// sits inside the ring it reports on and `HelmDurationField`'s 34 twice is
    /// «the hero's figure, one down» — a step the scale does not have, since it
    /// goes 22 · 40. Moving either is redrawing a screen, and the reason is at
    /// each line.
    ///
    /// **4 on 2026-08-20, and the tree did not drift — the scan grew.** This
    /// number is only ever lowered, so an increase has to say what changed, and
    /// what changed is which files are read: `Sources/HelmApp` was never
    /// scanned, and the shell held twelve hand-typed sizes nobody was counting.
    /// Eleven of them size a symbol rather than a word and are now excluded on
    /// purpose (see `hits()`); of the two that are really type, the composer
    /// sheet's heading went to 16 — the step `HelmPageHeader` already sets a
    /// page title on, which is the rank a sheet's title reads at — and the
    /// fourth is the About page's «Helm» wordmark at 34. That is the same
    /// figure `HelmDurationField` is excused for and the same reason: the scale
    /// goes 22 · 40, the wordmark belongs between them, and moving it is
    /// redrawing the About page rather than tidying a number.
    ///
    /// **3 on 2026-08-21.** `HelmDurationField`'s 34 was written twice in one
    /// file, at the colon and at the boxes; it is one held `digitFont` there
    /// now, so the same excused size is spelled once. Nothing was resized — the
    /// count fell because a duplicate went away, which is the only kind of
    /// lowering this ratchet ever wanted.
    private static let recorded = 3
    private static let ladder: Set<Double> = [10, 11, 13, 16, 22, 40]

    private static let patterns = [
        #"\.system\(\s*size:\s*(-?\d+(?:\.\d+)?)"#,
        #"\bsystemFont\(ofSize:\s*(-?\d+(?:\.\d+)?)"#,
        #"\bmonospacedSystemFont\(ofSize:\s*(-?\d+(?:\.\d+)?)"#,
        #"\bmonospacedDigitSystemFont\(ofSize:\s*(-?\d+(?:\.\d+)?)"#,
    ]

    /// Every hand-typed size in a file that draws, **minus the ones sizing a
    /// symbol rather than a word** (`UISources.sizingType`, which carries that
    /// distinction and the reason for it).
    ///
    /// This scan read `UISources.files()` — `HelmUI` and the module pages —
    /// until 2026-08-20, and not `Sources/HelmApp`. Twelve hand-typed sizes
    /// were sitting in the shell it did not read: the panel, its chrome, the
    /// composer sheet and the About page. A ladder guarded everywhere except
    /// the surface a person opens most is not a ladder. **Eleven of those
    /// twelve were `Image(systemName:)`** — which is what the filter is for.
    ///
    /// So the file set widens and the subject narrows, in the same commit. What
    /// governs a glyph's size is a separate question and is not answered here;
    /// nothing measures it yet, and that is written down rather than implied.
    private func hits() throws -> [UISources.Hit] {
        try UISources.sizingType(
            UISources.hits(matching: Self.patterns, in: UISources.everyDrawnFile()))
    }

    func testTypeOffTheScaleDoesNotGrow() throws {
        let off = UISources.offLadder(try hits(), ladder: Self.ladder)
        XCTAssertLessThanOrEqual(off.count, Self.recorded, """
            \(off.count) hand-typed font sizes are off the scale \
            \(Self.ladder.sorted().map { String(Int($0)) }.joined(separator: "·")); \
            the recorded number is \(Self.recorded).
            This number is only ever lowered, by the commit that lowers it.
            \(UISources.summary(off))
            """)
    }

    /// **The filter above can swallow the scan, and then nothing fails.**
    ///
    /// `off.count <= recorded` is satisfied by zero, so a `UISources.sizingType`
    /// that dropped everything would leave the ratchet guarding an empty
    /// set and reporting success — the shape ARCHITECTURE.md § A check that
    /// cannot fail is not a check collects. So the scan states what it still
    /// sees: files, sizes, and sizes that are on the ladder rather than off it.
    ///
    /// The last of those three is the one that matters. A scan finding only
    /// off-ladder sizes would also be a scan that had stopped reading most of
    /// the tree.
    func testTheScanStillHasTypeToJudge() throws {
        XCTAssertGreaterThan(try UISources.everyDrawnFile().count, 50,
                             "the file list has collapsed; every ratchet over it is idle")
        let seen = try hits()
        XCTAssertGreaterThan(seen.count, 20, """
            the scan sees \(seen.count) hand-typed sizes in the whole app. Either the tree \
            really has that few, or `UISources.sizingType` is dropping type — and the \
            ratchet above \
            passes either way, which is why this floor is here
            """)
        XCTAssertGreaterThan(seen.filter { Self.ladder.contains($0.value) }.count, 15,
                             "the scan finds almost nothing on the ladder, so it is not "
                             + "reading the files where the scale is actually kept")
    }

    // MARK: - The second unit: a size that was named rather than typed

    /// A style whose size is on no step of the scale.
    ///
    /// `.callout` is 12 and `.title3` is 15 — two of the seventeen sizes the
    /// mockups carried, arriving under a role name so that nobody typing one
    /// had to notice. The floor here is genuinely 0: every one of them has a
    /// step to go to, and where the *role* is right and the size is not, the
    /// answer is one of `HelmText`'s four tokens.
    ///
    /// Wider than the ladder scans on purpose — `everyDrawnFile()`, so the app
    /// shell is read too. A vocabulary that stops at the module boundary is not
    /// the app's vocabulary.
    ///
    /// **1**, measured 2026-08-12 against `main` = `83af00f` after the sweep,
    /// down from 33. The one that stays is `PanelChrome`'s module name: 12 is
    /// off the settings scale and on the *panel's* own — 9 · 10 · 11 · 12 in
    /// that file — and the menu-bar panel deliberately does not follow the
    /// settings language (ARCHITECTURE.md § Design language). The reason is at
    /// the line as well as here.
    private static let recordedOffScaleStyles = 1

    /// A style that resolves to 10 where the step a note uses is 11.
    ///
    /// `.caption`, `.caption2` and `.footnote` are three names for **one** size
    /// on macOS, so a file writing a heading in `.caption` over a detail in
    /// `.caption2` has drawn one size and written two — the hierarchy is in the
    /// source and not on the screen. `HelmText.rowDetail` is 11 and is what a
    /// note under a control is set in.
    ///
    /// **The floor is not 0, and that is the point of recording it.** 10 is a
    /// step of the scale, and a tick label under a picture card or a pill's own
    /// word means it. What this number says is how many sites still claim it —
    /// each of which carries the reason at the line, or should.
    ///
    /// **6**, measured 2026-08-12 against `main` = `83af00f` after the sweep,
    /// down from 89. Every one carries its reason at the line: four are on the
    /// menu-bar panel, which keeps its own scale; `HelmChoiceCards` and
    /// `BadgePreview` are tick labels under a picture whose tile widths were
    /// measured at this size; `HistorySection`'s is a timestamp in a 96 pt
    /// column that 11 pt overflows in two languages.
    private static let recordedCaptions = 6

    /// The three styles that resolve to 10, and the four that are off the scale
    /// altogether, with the size macOS gives each. Measured, not assumed:
    /// `testTheStylesStillResolveWhereTheyDid` reads them back off `NSFont`.
    private static let offScaleStyles: [String: Double] = [
        #"\.font\(\.callout\b"#: 12,
        #"\.font\(\.title2\b"#: 17,
        #"\.font\(\.title3\b"#: 15,
        #"\.font\(\.largeTitle\b"#: 26,
    ]

    private static let tenPointStyles: [String: Double] = [
        #"\.font\(\.caption\b(?!2)"#: 10,
        #"\.font\(\.footnote\b"#: 10,
    ]

    /// Both style families as one table, which is what a fixture wants and
    /// what neither ratchet wants: they are separate above so each carries its
    /// own recorded number and its own reason.
    private static var everyStyle: [String: Double] {
        offScaleStyles.merging(tenPointStyles) { first, _ in first }
    }

    func testASemanticStyleOffTheScaleDoesNotGrow() throws {
        let sites = try UISources.sites(matching: Self.offScaleStyles,
                                        in: UISources.everyDrawnFile())
        XCTAssertLessThanOrEqual(sites.count, Self.recordedOffScaleStyles, """
            \(sites.count) font styles resolve to a size on no step of \
            \(Self.ladder.sorted().map { String(Int($0)) }.joined(separator: "·")); \
            the recorded number is \(Self.recordedOffScaleStyles).
            This number is only ever lowered, by the commit that lowers it.
            \(UISources.summary(sites))
            """)
    }

    func testACaptionWhereTheStepIsElevenDoesNotGrow() throws {
        let sites = try UISources.sites(matching: Self.tenPointStyles,
                                        in: UISources.everyDrawnFile())
        XCTAssertLessThanOrEqual(sites.count, Self.recordedCaptions, """
            \(sites.count) sites are set in a style macOS resolves to 10 pt, where the \
            step a note under a control uses is 11 (`HelmText.rowDetail`); the recorded \
            number is \(Self.recordedCaptions).
            Where 10 is meant, the reason belongs at the line — and this number carries it.
            \(UISources.summary(sites))
            """)
    }

    /// **The premise, measured.** Both ratchets above rest on what macOS
    /// resolves a style to, which is not this repository's fact to assert. If a
    /// release moves `.callout` onto the scale, the first ratchet is guarding
    /// nothing and should be deleted rather than left green; if it moves
    /// `.caption2` off 10, the second one's whole complaint — three names, one
    /// size — has evaporated.
    func testTheStylesStillResolveWhereTheyDid() {
        XCTAssertEqual(NSFont.preferredFont(forTextStyle: .callout).pointSize, 12)
        XCTAssertEqual(NSFont.preferredFont(forTextStyle: .title3).pointSize, 15)
        XCTAssertEqual(NSFont.preferredFont(forTextStyle: .title2).pointSize, 17)
        for style in [NSFont.TextStyle.caption1, .caption2, .footnote] {
            XCTAssertEqual(NSFont.preferredFont(forTextStyle: style).pointSize, 10,
                           "\(style) no longer resolves to 10 — the three-names-one-size "
                           + "complaint this ratchet is built on has changed")
        }
        XCTAssertEqual(NSFont.preferredFont(forTextStyle: .body).pointSize, 13,
                       "body is the scale's own 13, which is why a sentence on a page "
                       + "takes `HelmText.rowTitle` rather than a fifth token")
    }

    /// And the style scan is still matching, which is the half that goes quiet.
    /// `.caption2` is deliberately outside both ratchets — it is the honest
    /// spelling of the 10 pt step — so it is the control: the same family of
    /// patterns finds plenty of it, in both targets the scan claims to read.
    func testTheStyleScanStillReadsBothTargets() throws {
        let files = try UISources.everyDrawnFile()
        XCTAssertTrue(files.contains { $0.hasPrefix("Sources/HelmApp/") },
                      "the style scan is not reading the app shell")
        XCTAssertTrue(files.contains { $0.hasPrefix("Sources/HelmUI/") },
                      "the style scan is not reading the design system")
        let control = try UISources.sites(matching: [#"\.font\(\.caption2\b"#: 10], in: files)
        XCTAssertGreaterThan(control.count, 5,
                             "the style patterns matched \(control.count) uses of `.caption2` — "
                             + "a family that has stopped matching reports no offenders for ever")
    }

    /// The rule objects to the shape it was written for and lets the tokens
    /// through, against a fixture rather than the tree.
    func testTheStyleRuleReadsAStyleAndNotAToken() throws {
        let fixture = try UISources.sites(matching: Self.everyStyle, in: """
            Text("a").font(.callout)
            Text("b").font(.caption).foregroundStyle(HelmText.quiet)
            Text("c").font(HelmText.rowDetail)
            Text("d").font(.caption2)
            """).sorted { $0.line < $1.line }
        XCTAssertEqual(fixture.map(\.value), [12, 10],
                       "the callout and the caption are the two it must see; the token and "
                       + "`.caption2` are the two it must not")
    }

    // MARK: - The scan itself

    /// The same floor the space ladder asserts, for the same reason: a pattern
    /// that has stopped matching reports no offenders and passes for ever.
    /// Most hand-typed sizes are already on the scale, and that is what makes
    /// the small number above readable as a small number.
    func testTheScanStillFindsFontSizesAtAll() throws {
        let all = try hits()
        // The floor is «obviously more than none», not a census: it exists so a
        // pattern that has stopped matching fails instead of passing for ever.
        // It came down from 30 when Keyboard's three hand-typed monospaced
        // faces became `.system(.body, design: .monospaced)` — a size that
        // follows the Mac's text setting is one fewer size to scan, which is
        // the direction this whole file wants.
        XCTAssertGreaterThan(all.count, 20, "the type patterns matched \(all.count) sizes")
        XCTAssertLessThan(UISources.offLadder(all, ladder: Self.ladder).count, all.count / 2,
                          "more than half of every hand-typed size is off the scale — "
                          + "either the scale is wrong or the scan is")
    }

    /// The rule objects to the shape it was written for, and lets the scale
    /// through. Against a fixture, so it goes on saying this after the tree is
    /// fixed.
    func testTheRuleRecognisesASizeOffTheScale() throws {
        let off = try UISources.hits(matching: Self.patterns, in: #"Text("x").font(.system(size: 15, weight: .semibold))"#)
        XCTAssertEqual(off.map(\.value), [15])
        XCTAssertEqual(UISources.offLadder(off, ladder: Self.ladder).count, 1)

        let on = try UISources.hits(matching: Self.patterns, in: #"Text("x").font(.system(size: 13))"#)
        XCTAssertEqual(on.map(\.value), [13])
        XCTAssertEqual(UISources.offLadder(on, ladder: Self.ladder), [])
    }

    /// `NSFont` is the other half. `MenuBarLook` and the icon drawing reach for
    /// it directly, and a size typed there is as much a size as one typed in
    /// SwiftUI.
    func testTheRuleReadsTheAppKitBuildersToo() throws {
        let hits = try UISources.hits(matching: Self.patterns, in: "NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)")
        XCTAssertEqual(hits.map(\.value), [9])
    }

}
