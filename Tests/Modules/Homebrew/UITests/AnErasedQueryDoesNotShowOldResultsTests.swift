import XCTest
import HelmTestSupport
@testable import Module_Homebrew_UI
@testable import Module_Homebrew_Engine

/// Erasing the search field must retire the section, not leave the previous
/// query's answer sitting under whatever is on screen. `SearchDisplay` used
/// to own this decision for a segment of its own; `AvailableSection` is the
/// same seam for the section that now sits under every tab's own list —
/// rewritten onto it 2026-09-24 rather than deleted, since the lessons below
/// still hold.
final class AnErasedQueryDoesNotShowOldResultsTests: XCTestCase {
    private static let hit = SearchHit(name: "wget", isCask: false)

    /// An empty or whitespace-only query draws nothing, even with an old
    /// answer still held — the previous search's hits must not outlive the
    /// query that asked for them.
    func testAnEmptyQueryDrawsNothingEvenWithOldHitsStillHeld() {
        XCTAssertNil(AvailableSection.of(query: "", searchedQuery: "wget", reading: .answered,
                                         available: [Self.hit]))
    }

    /// The engine refuses a whitespace-only query (`search` trims before it
    /// runs), so a section over one would belong to no query.
    func testAWhitespaceQueryIsAnEmptyQuery() {
        XCTAssertNil(AvailableSection.of(query: "   ", searchedQuery: "wget", reading: .answered,
                                         available: [Self.hit]))
    }

    /// Nobody has asked brew about this word yet — the ordinary state between
    /// mounting and the first ask, and while the pause is still counting down.
    func testNothingAskedYetDrawsNothing() {
        XCTAssertNil(AvailableSection.of(query: "wget", searchedQuery: nil, reading: .notAsked,
                                         available: []))
    }

    /// **A word typed over the one that was searched draws nothing, even
    /// though the old answer is still held.** Refining `wget` down to `wg`
    /// must not flash `wget`'s hits under the new, shorter word — the section
    /// comes back only once `wg` itself has been asked.
    func testAWordTypedOverTheSearchedOneDrawsNothing() {
        XCTAssertNil(AvailableSection.of(query: "wg", searchedQuery: "wget", reading: .answered,
                                         available: [Self.hit]))
    }

    func testAWaitingSearchIsSearching() {
        XCTAssertEqual(AvailableSection.of(query: "wget", searchedQuery: "wget", reading: .waiting,
                                           available: []),
                       .searching)
    }

    func testAnAnsweredSearchWithNoHitsIsNothingFound() {
        XCTAssertEqual(AvailableSection.of(query: "wget", searchedQuery: "wget", reading: .answered,
                                           available: []),
                       .nothingFound)
    }

    func testAnAnsweredSearchWithHitsIsFound() {
        XCTAssertEqual(AvailableSection.of(query: "wget", searchedQuery: "wget", reading: .answered,
                                           available: [Self.hit]),
                       .found)
    }

    func testARefusedSearchIsUnanswerable() {
        XCTAssertEqual(AvailableSection.of(query: "wget", searchedQuery: "wget", reading: .unanswerable,
                                           available: []),
                       .unanswerable)
    }

    /// The seam only guards the page if the page reads it: the decision used
    /// to be inline in `body`, which is where it was unpinnable. Structural,
    /// the way `MemoryTrailCoverageTests` reads its labels.
    func testThePageReadsTheSeam() throws {
        let page = RepoSource.root
            .appendingPathComponent("Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift")
        let source = try String(contentsOf: page, encoding: .utf8)
        XCTAssertTrue(source.contains("hb.section"),
                      "HomebrewSettingsPage no longer reads the view model's own AvailableSection")
    }
}
