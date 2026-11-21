import XCTest
@testable import Module_Launchpad_Engine

/// The category view's blocks, pure: who is in which block, in what order. Each case first proves the block it asserts about exists.
final class ACategoryNeverShowsAHiddenAppAndKeepsEveryOtherOnceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ d: Double, hours h: Double = 0) -> Date { now.addingTimeInterval(-(d * 86_400 + h * 3_600)) }

    private func app(_ id: String, _ category: String?, added: Date? = nil) -> CatalogApp {
        CatalogApp(id: id, name: id, path: "/Applications/\(id).app", category: category.map { "public.app-category.\($0)" }, added: added)
    }

    private func blocks(_ apps: [CatalogApp], hidden: Set<String> = [], counts: [String: Int] = [:]) -> [LaunchpadCategoryBlock] {
        LaunchpadCategories.blocks(apps: apps, hidden: hidden, counts: counts, now: now) { kind in
            switch kind {
            case .recent: "Recently Added"
            case .others: "Others"
            case .category(let c): c.rawValue
            }
        }
    }

    private func ids(_ block: LaunchpadCategoryBlock?) -> [String] { block?.apps.map(\.id) ?? [] }
    private func block(_ kind: LaunchpadCategoryBlock.Kind, in all: [LaunchpadCategoryBlock]) -> LaunchpadCategoryBlock? { all.first { $0.kind == kind } }

    func testAHiddenAppIsInNoBlockRecentlyAddedIncluded() {
        let apps = [app("a", "music", added: days(1)), app("b", "music", added: days(1)), app("c", nil)]
        let shown = blocks(apps)
        XCTAssertEqual(ids(block(.recent, in: shown)), ["a", "b"], "the control: both are recent before one is hidden")
        let all = blocks(apps, hidden: ["a"])
        XCTAssertEqual(ids(block(.recent, in: all)), ["b"])
        XCTAssertEqual(ids(block(.category(.music), in: all)), ["b"])
        XCTAssertFalse(all.flatMap(\.apps).contains { $0.id == "a" })
        XCTAssertTrue(blocks(apps, hidden: ["a", "b", "c"]).isEmpty, "everything hidden: no block at all")
    }

    func testEveryVisibleAppIsInExactlyOneCategoryBlockAndAtMostOnceMoreInRecentlyAdded() {
        let apps = [app("a", "music", added: days(2)), app("b", "games"), app("c", "puzzle-games"), app("d", nil), app("e", "made-up"),
                    app("f", "weather", added: days(40)), app("g", "utilities", added: days(3))]
        let all = blocks(apps)
        XCTAssertGreaterThan(all.count, 3)
        let inCategories = all.filter { $0.kind != .recent }.flatMap(\.apps).map(\.id)
        XCTAssertEqual(inCategories.sorted(), apps.map(\.id).sorted(), "each app once among the categories and Others")
        XCTAssertEqual(ids(block(.others, in: all)), ["d", "e"], "no category and an unknown one are Others")
        XCTAssertEqual(ids(block(.category(.games), in: all)), ["b", "c"], "a games subtype is Games")
        XCTAssertEqual(Set(ids(block(.recent, in: all))), ["a", "g"])
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "block ids are distinct")
    }

    func testBlocksGoByLaunchesTiesByNameOthersLastRecentFirstAndAppsByOwnCount() {
        let apps = [app("a", "music"), app("b", "music"), app("c", "weather"), app("d", "sports"), app("e", nil), app("f", "weather"),
                    app("n", "news", added: days(1))]
        let counts = ["a": 1, "b": 5, "c": 2, "d": 3, "e": 100, "f": 4]
        let all = blocks(apps, counts: counts)
        XCTAssertEqual(all.map(\.kind), [.recent, .category(.music), .category(.weather), .category(.sports), .category(.news), .others],
                       "Recently Added first; music 6 and weather 6 tie, so by name; sports 3, news 0; Others last with 100")
        XCTAssertEqual(ids(block(.category(.music), in: all)), ["b", "a"], "own count first")
        XCTAssertEqual(ids(block(.category(.weather), in: all)), ["f", "c"])
        XCTAssertEqual(block(.others, in: all)?.launches, 100)
        let alphabetical = blocks([app("a", "weather"), app("b", "music"), app("c", "news")])
        XCTAssertEqual(alphabetical.map(\.kind), [.category(.music), .category(.news), .category(.weather)], "no launches: ties by name")
        let tied = blocks([app("x", "music"), app("y", "music"), app("z", "music")], counts: ["x": 2, "y": 2, "z": 2])
        XCTAssertEqual(ids(tied.first), ["x", "y", "z"], "equal counts keep catalog order")
    }

    func testRecentlyAddedIsOnlyThereWhenItHasAppsAndGoesNewestFirst() {
        let none = blocks([app("a", "music", added: days(31))])
        XCTAssertEqual(none.map(\.kind), [.category(.music)], "nothing recent: no block")
        let some = blocks([app("a", "music", added: days(5)), app("b", "music", added: days(1)), app("c", "music", added: days(5))], counts: ["a": 9])
        XCTAssertEqual(ids(block(.recent, in: some)), ["b", "a", "c"], "newest first, then catalog order, whatever the counts")
        XCTAssertEqual(some.first?.kind, .recent)
    }

    func testTheRecentBoundaries() {
        let apps = [app("in", "music", added: days(29, hours: 23)), app("out", "music", added: days(30, hours: 1)),
                    app("future", "music", added: now.addingTimeInterval(3_600)), app("none", "music"), app("now", "music", added: now)]
        XCTAssertEqual(Set(ids(block(.recent, in: blocks(apps)))), ["in", "now"])
        XCTAssertEqual(ids(block(.category(.music), in: blocks(apps))).count, 5, "the control: all five are in Music")
    }

    func testABlocksIdIsFixedAndTheCategoryNeverMovesAnother() {
        let kinds: [LaunchpadCategoryBlock.Kind] = [.recent, .others] + LaunchpadCategory.allCases.map { .category($0) }
        let made = kinds.map { LaunchpadCategoryBlock(kind: $0, apps: [], launches: 0).id }
        XCTAssertEqual(Set(made).count, kinds.count)
        XCTAssertEqual(made, kinds.map { LaunchpadCategoryBlock(kind: $0, apps: [app("x", nil)], launches: 3).id })
        XCTAssertEqual(LaunchpadCategory.allCases.count, 28)
    }

    func testTheLaunchesOfABlockSaturateAndOthersIsNotACategory() {
        let all = blocks([app("a", "music"), app("b", "music")], counts: ["a": Int.max, "b": 5])
        XCTAssertEqual(block(.category(.music), in: all)?.launches, Int.max)
        XCTAssertNil(LaunchpadCategory(raw: "public.app-category.other"))
        XCTAssertNil(LaunchpadCategory(raw: "music"))
        XCTAssertEqual(LaunchpadCategory(raw: "PUBLIC.APP-CATEGORY.Action-Games"), .games)
    }
}
