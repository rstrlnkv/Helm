import XCTest
@testable import Module_Homebrew_Engine

/// What a search for `hello` should put first.
///
/// `brew search` answers alphabetically, and Helm showed that order: searching
/// for `hello` on a real machine listed aws-shell, cmdshelf, couchbase-shell
/// and eleven more before `hello` itself, which sat between `helix-db` and
/// `hellwal` and needed two scrolls. Somebody who types a package's exact name
/// has already told you which one they mean.
final class SearchRankingTests: XCTestCase {

    private func names(_ names: [String], cask: Bool = false) -> [SearchHit] {
        names.map { SearchHit(name: $0, isCask: cask) }
    }

    func testTheExactNameComesFirst() {
        let hits = names(["aws-shell", "helix", "helix-db", "hello", "hellwal"])
        XCTAssertEqual(SearchRanking.rank(hits, query: "hello").first?.name, "hello")
    }

    /// Case is not a decision the person made about which package they mean.
    func testTheExactMatchIsFoundWhateverTheCase() {
        let hits = names(["Docker", "docker-compose"])
        XCTAssertEqual(SearchRanking.rank(hits, query: "DOCKER").first?.name, "Docker")
    }

    /// After the exact name: the ones that start with what was typed, then
    /// everything else that merely contains it.
    func testPrefixesBeatSubstrings() {
        let hits = names(["aws-shell", "helix", "hello", "cmdshelf"])
        XCTAssertEqual(SearchRanking.rank(hits, query: "hel").map(\.name),
                       ["helix", "hello", "aws-shell", "cmdshelf"])
    }

    /// Inside a group brew's own order is kept — it is alphabetical, and
    /// resorting it would only make the list harder to scan.
    func testOrderIsOtherwiseUntouched() {
        let hits = names(["alpha", "beta", "gamma"])
        XCTAssertEqual(SearchRanking.rank(hits, query: "zzz").map(\.name),
                       ["alpha", "beta", "gamma"])
    }

    /// A formula and a cask can share a name. Both stay, both first.
    func testBothKindsOfExactMatchLead() {
        let hits = names(["aaa"]) + names(["docker"], cask: true) + names(["docker"])
        let ranked = SearchRanking.rank(hits, query: "docker")
        XCTAssertEqual(ranked.prefix(2).map(\.name), ["docker", "docker"])
    }

    func testAnEmptyQueryChangesNothing() {
        let hits = names(["b", "a"])
        XCTAssertEqual(SearchRanking.rank(hits, query: "  ").map(\.name), ["b", "a"])
    }
}
