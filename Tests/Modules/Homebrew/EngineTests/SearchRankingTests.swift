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

extension SearchRankingTests {

    private func hits(_ names: [String]) -> [SearchHit] {
        names.map { SearchHit(name: $0, isCask: false) }
    }

    /// The groups are not negotiable: an exact name beats a popular prefix — and
    /// inside the prefix group the popular one still comes first. Two claims,
    /// one fixture, because with a single hit per group the sort is never asked
    /// anything and the case passes with it deleted.
    func testAnExactNameStillWinsOverAPopularPrefix() {
        let ranked = SearchRanking.rank(hits(["node-build", "nodebrew", "node"]), query: "node",
                                        formulae: InstallCounts(counts: ["node": 1,
                                                                         "node-build": 5,
                                                                         "nodebrew": 99_999]),
                                        casks: .none)
        XCTAssertEqual(ranked.map(\.name), ["node", "nodebrew", "node-build"])
    }

    func testInsideAGroupTheMoreInstalledComesFirst() {
        let ranked = SearchRanking.rank(hits(["aws-shell", "hello-world", "helm"]),
                                        query: "hel",
                                        formulae: InstallCounts(counts: ["helm": 5_000,
                                                                         "hello-world": 12]),
                                        casks: .none)
        XCTAssertEqual(Array(ranked.map(\.name).prefix(2)), ["helm", "hello-world"])
    }

    /// A package nobody has installed is not the same as a package installed
    /// zero times by accident of a missing reading — either way it keeps brew's
    /// order and goes after the ones with a number.
    func testPackagesWithNoCountKeepTheirOrderAndComeLast() {
        let ranked = SearchRanking.rank(hits(["alpha", "beta", "gamma"]), query: "z",
                                        formulae: InstallCounts(counts: ["gamma": 3]),
                                        casks: .none)
        XCTAssertEqual(ranked.map(\.name), ["gamma", "alpha", "beta"])
    }

    /// A formula and a cask can share a name, and the two documents are
    /// separate. Both hits here are prefix matches, so the sort really does
    /// compare them — and the counts are planted so that reading a cask's rank
    /// out of the *formula* map would reverse the answer.
    func testACaskIsRankedByTheCaskDocument() {
        let mixed = [SearchHit(name: "docker-compose", isCask: false),
                     SearchHit(name: "docker-desktop", isCask: true)]
        let ranked = SearchRanking.rank(mixed, query: "docker",
                                        formulae: InstallCounts(counts: ["docker-compose": 50,
                                                                         "docker-desktop": 9_999]),
                                        casks: InstallCounts(counts: ["docker-desktop": 1]))
        XCTAssertEqual(ranked.map(\.name), ["docker-compose", "docker-desktop"],
                       "the cask was ranked by the formula document")
    }

    /// Guards that the default is `.none` and not something else: the
    /// two-argument call must agree with an explicit `.none, .none` call.
    func testWithNoReadingsNothingMoves() {
        let names = ["aws-shell", "cmdshelf", "hello", "helix-db"]
        XCTAssertEqual(SearchRanking.rank(hits(names), query: "hello").map(\.name),
                       SearchRanking.rank(hits(names), query: "hello",
                                          formulae: .none, casks: .none).map(\.name))
    }
}
