import XCTest
import HelmTestSupport
@testable import Module_Homebrew_UI

/// Erasing the search field must bring back the "type a name" prompt, not the
/// previous query's results. The page used to branch on
/// `query.isEmpty && hb.searchHits.isEmpty`, so old hits pinned the results
/// list on screen over an empty field — and the branch lived on a private
/// `@State`, where no test could reach it. `SearchDisplay` is the seam: it owns
/// the whole decision, and the body reads it.
final class AnErasedQueryDoesNotShowOldResultsTests: XCTestCase {

    func testAnEmptyQueryShowsThePromptEvenWithOldHitsStillHeld() {
        XCTAssertEqual(SearchDisplay.state(query: "", reading: .answered), .prompt,
                       "the previous search's results outlived the query that asked for them")
    }

    /// The engine refuses a whitespace-only query (`search` trims before it
    /// runs), so the page showing results over one shows results no query owns.
    func testAWhitespaceQueryIsAnEmptyQuery() {
        XCTAssertEqual(SearchDisplay.state(query: "   ", reading: .answered), .prompt)
    }

    func testATypedQueryShowsTheResultsArea() {
        XCTAssertEqual(SearchDisplay.state(query: "wget", reading: .waiting), .results)
        XCTAssertEqual(SearchDisplay.state(query: "wget", reading: .answered), .results)
        XCTAssertEqual(SearchDisplay.state(query: "wget", reading: .unanswerable), .results)
    }

    /// **A word typed with Return not yet pressed is still the prompt.**
    ///
    /// The results area now says which of three things is true — a search is
    /// running, it answered nothing, it could not be put — and none of the
    /// three is true of somebody who is still typing. Drawn from the query
    /// alone, that person got the busy spinner and «Searching…» over a `brew`
    /// nobody had started.
    func testATypedQueryNobodyHasSubmittedIsStillThePrompt() {
        XCTAssertEqual(SearchDisplay.state(query: "wget", reading: .notAsked), .prompt,
                       "a word that has not been submitted drew an answer to a question nobody asked")
    }

    /// The seam only guards the page if the page reads it: the decision used to
    /// be inline in `body`, which is where it was unpinnable. Structural, the
    /// way `MemoryTrailCoverageTests` reads its labels.
    func testThePageReadsTheSeam() throws {
        let page = RepoSource.root
            .appendingPathComponent("Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift")
        let source = try String(contentsOf: page, encoding: .utf8)
        XCTAssertTrue(source.contains("SearchDisplay.state("),
                      "HomebrewSettingsPage no longer decides the search area through SearchDisplay")
    }
}
