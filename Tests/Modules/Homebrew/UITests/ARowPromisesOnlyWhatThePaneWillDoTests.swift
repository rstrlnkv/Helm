import XCTest
import HelmTestSupport
@testable import Module_Homebrew_UI

/// **A chevron on a row is a promise that pressing it opens something, and
/// this page can only keep that promise at one width.**
///
/// Below `HomebrewSplit`'s threshold the list is the whole pane and a press
/// replaces it with the row's own screen; above it the same press moves the
/// inspector already standing beside the list, and the pane does not change.
/// Drawn in both places the mark says «this goes somewhere» over a page that
/// goes nowhere — and drawn in neither, the single-column list offers no sign
/// at all that its rows lead anywhere, which is the state this module shipped
/// in until now.
///
/// **Two halves, and they fail for different reasons.**
///
/// The first is behavioural: `singleColumn` and `showsInspector` are one fact,
/// so a second threshold cannot be introduced for the mark without this
/// noticing — a page that drew the chevron from its own `width < 500` would
/// have two boundaries and only one of them would ever be re-measured.
///
/// The second is a source scan, for the reason
/// `TheRowsUpdateMarkerIsMoreThanAColourTests` gives at length: `NSHostingView`
/// builds no accessibility tree until a client connects, so nothing this suite
/// can mount will say what VoiceOver reads, and a chevron is ink with no name
/// in the render either. It therefore proves the construction and not the
/// reading: that every row that pushes asks for the mark, that the mark is
/// gated on the one fact, and that the hint which carries the promise in words
/// is gated on the same one. It does not prove the chevron is legible or the
/// hint well worded.
final class ARowPromisesOnlyWhatThePaneWillDoTests: XCTestCase {

    private static let page = "Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift"

    // MARK: - One fact, not two thresholds

    /// Swept rather than sampled at the boundary: a sample either side passes
    /// for any single threshold at all, and what this has to catch is a
    /// *second* one. Monotonic in the opposite direction to `showsInspector`,
    /// and never both or neither at any width.
    func testTheListKnowsItIsAloneExactlyWhenTheInspectorIsNotThere() {
        var wasSingle = true
        for width in stride(from: CGFloat(200), through: 1200, by: 1) {
            let split = HomebrewSplit(availableWidth: width)
            XCTAssertEqual(split.singleColumn, !split.showsInspector,
                           "at \(width) pt the page disagrees with itself about whether the list "
                           + "is the whole pane")
            if !split.singleColumn { wasSingle = false }
            XCTAssertFalse(split.singleColumn && !wasSingle,
                           "the single-column answer came back at \(width) pt after it had "
                           + "already gone — a second threshold is hiding behind this one")
        }
        XCTAssertFalse(wasSingle, "the pane is single-column at every width in the sweep")
    }

    // MARK: - Every row that pushes says so

    /// The builders whose rows lead to their own screen, and what each one
    /// draws so the scan can assert the subject before the promise — a row
    /// that stopped being drawn at all would otherwise satisfy a rule about
    /// how it marks itself. The configuration sections are the third kind of
    /// pushing row and are built inline; the case below them names those.
    private static let pushingRows = [
        (builder: "pkgRow", draws: "Text(name)"),
        (builder: "issueRow", draws: "Text(issue.title)")
    ]

    func testEveryRowThatOpensAScreenAsksForTheMarkAndTheHint() throws {
        let source = try RepoSource.text(of: Self.page)
        let code = SwiftSource.uncommented(source)

        for row in Self.pushingRows {
            guard let body = SwiftSource.body(of: row.builder, in: code) else {
                XCTFail("\(Self.page) no longer declares \(row.builder) — this rule is about the "
                        + "rows it draws")
                continue
            }
            XCTAssertTrue(body.contains(row.draws),
                          "\(row.builder) no longer draws \(row.draws): the rule below would pass "
                          + "over a row with nothing in it")
            XCTAssertTrue(body.contains("goesToItsOwnScreen("),
                          "\(row.builder) draws no chevron, so in the single-column pane its rows "
                          + "give no sign that pressing one replaces the list")
            XCTAssertTrue(body.contains("helmOpensAScreen("),
                          "\(row.builder) carries no hint, so VoiceOver reads its rows exactly as "
                          + "it reads the two-column page's — the press is announced nowhere")
        }
    }

    /// The configuration rows are built inline in `healthList` rather than in a
    /// builder of their own, and they push the same way. Named here so adding
    /// the mark to the findings and forgetting the sections cannot pass.
    func testTheConfigurationSectionsCarryTheMarkToo() throws {
        let source = try RepoSource.text(of: Self.page)
        let code = SwiftSource.uncommented(source)
        guard let body = SwiftSource.body(of: "healthList", in: code) else {
            XCTFail("\(Self.page) no longer declares healthList")
            return
        }
        XCTAssertTrue(body.contains("HbStr.configSectionName("),
                      "healthList no longer draws the configuration sections")
        // Two rows in this list push — a finding and a section — and the
        // finding's mark lives in `issueRow`, so a single occurrence here is
        // the section's own.
        XCTAssertTrue(body.contains("goesToItsOwnScreen("),
                      "the configuration sections draw no chevron, so half the rows of Состояние "
                      + "promise a screen and the other half do not")
        XCTAssertTrue(body.contains("helmOpensAScreen("),
                      "the configuration sections carry no hint")
    }

    // MARK: - The mark is gated, and so is the hint

    /// Both helpers must be conditional on the fact they were given. Without
    /// the gate the chevron is drawn beside a list that already has the
    /// inspector open next to it, and the hint tells a VoiceOver reader the
    /// press will replace a pane that stays where it is.
    func testNeitherTheMarkNorTheHintIsDrawnUnconditionally() throws {
        let source = try RepoSource.text(of: Self.page)
        let code = SwiftSource.uncommented(source)

        for helper in ["goesToItsOwnScreen", "helmOpensAScreen"] {
            guard let body = SwiftSource.body(of: helper, in: code) else {
                XCTFail("\(Self.page) no longer declares \(helper)")
                continue
            }
            XCTAssertTrue(body.contains("if singleColumn"),
                          "\(helper) draws whatever it draws at every width — the wide page then "
                          + "makes a promise it cannot keep")
        }
    }

    /// The words themselves are a key like every other, so the eight
    /// `.strings` files hold it — `StringsCoverageTests` is what enforces
    /// that. What is asserted here is only that the hint is not a literal
    /// spelled at the call site, which is the one way it could reach a person
    /// in English on a Russian Mac.
    func testTheHintIsALookupAndNotALiteral() throws {
        let source = try RepoSource.text(of: Self.page)
        let code = SwiftSource.uncommented(source)
        guard let body = SwiftSource.body(of: "helmOpensAScreen", in: code) else {
            XCTFail("\(Self.page) no longer declares helmOpensAScreen")
            return
        }
        XCTAssertTrue(body.contains("HbStr.opensItsOwnScreen"),
                      "the hint is spelled in this file rather than looked up, so seven languages "
                      + "read it in English")
    }
}
