import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// The inputs pass 15 did not feed to the engine: a move of a hidden app, a move that outlives hide and unhide, a stale second move,
/// a hand-edited move onto the app's own category, a move whose app is absent from an incomplete read and then from a complete one,
/// a move into a category nobody else has, and Reset arrangement with a move in the file. Each case first proves the move is there.
final class AMoveUntriedInputsTests: XCTestCase {
    private func catalog(_ ids: [String] = ["a", "b", "c", "d"], complete: Bool = true) -> FakeAppCatalog {
        let fake = FakeAppCatalog()
        fake.reading = CatalogReading(apps: ids.map {
            CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app", category: $0 == "d" ? nil : "public.app-category.music")
        }, complete: complete)
        return fake
    }

    private func engine(_ dir: URL, _ catalog: FakeAppCatalog? = nil) -> LaunchpadEngine {
        LaunchpadEngine(catalog: catalog ?? self.catalog(), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
    }

    private func file(_ dir: URL) -> Data? { try? Data(contentsOf: dir.appendingPathComponent("layout.json")) }

    private func blocks(_ s: LaunchpadSnapshot, counts: [String: Int] = [:]) -> [LaunchpadCategoryBlock] {
        LaunchpadCategories.blocks(apps: s.order.compactMap { s.apps[$0] }, hidden: s.layout.hidden, counts: counts, now: Date(),
                                   overrides: s.layout.categoryOverrides) { "\($0)" }
    }

    private func ids(_ kind: LaunchpadCategoryBlock.Kind, _ s: LaunchpadSnapshot, counts: [String: Int] = [:]) -> [String]? {
        blocks(s, counts: counts).first { $0.kind == kind }?.apps.map(\.id)
    }

    func testAHiddenAppCanBeMovedAndAppearsInItsNewBlockOnlyWhenShown() throws {
        let e = engine(scratchDirectory("moved-hidden"))
        _ = e.read(reason: .refresh)
        let hidden = try XCTUnwrap(e.apply(.hide("a")))
        XCTAssertEqual(hidden.layout.hidden, ["a"], "subject: a is hidden")
        let moved = try XCTUnwrap(e.apply(.setCategory("a", .category(.games))), "a hidden app can be moved")
        XCTAssertEqual(moved.layout.categoryOverrides, ["a": .category(.games)])
        XCTAssertNil(ids(.category(.games), moved), "hidden: in no block, and no block is made for it")
        let back = try XCTUnwrap(e.apply(.unhide("a")))
        XCTAssertEqual(ids(.category(.games), back), ["a"], "unhidden: in the block it was sent to while hidden")
        XCTAssertEqual(ids(.category(.music), back)?.sorted(), ["b", "c"])
    }

    func testAMoveThenHideThenUnhideKeepsTheMoveAndTheBlock() throws {
        let dir = scratchDirectory("moved-hide-unhide")
        let e = engine(dir)
        _ = e.read(reason: .refresh)
        let moved = try XCTUnwrap(e.apply(.setCategory("b", .others)))
        XCTAssertEqual(ids(.others, moved)?.sorted(), ["b", "d"], "subject: b is in Others")
        let hidden = try XCTUnwrap(e.apply(.hide("b")))
        XCTAssertEqual(ids(.others, hidden), ["d"])
        let shown = try XCTUnwrap(e.apply(.unhide("b")))
        XCTAssertEqual(ids(.others, shown)?.sorted(), ["b", "d"])
        XCTAssertEqual(engine(dir).read(reason: .refresh).layout.categoryOverrides, ["b": .others], "and the file says so")
    }

    func testAMoveToACategoryNobodyElseHasMakesABlockAndItsOrderFollowsTheCounts() throws {
        let e = engine(scratchDirectory("moved-new-block"))
        _ = e.read(reason: .refresh)
        XCTAssertNil(ids(.category(.games), e.read(reason: .refresh)), "subject: no Games block before")
        let one = try XCTUnwrap(e.apply(.setCategory("d", .category(.games))))
        XCTAssertEqual(ids(.category(.games), one), ["d"])
        XCTAssertNil(ids(.others, one), "d was Others' only app: Others is gone")
        let counts = ["d": 50, "a": 2, "b": 1]
        let order = blocks(one, counts: counts).filter { $0.kind != .recent }.map(\.kind)
        XCTAssertEqual(order, [.category(.games), .category(.music)], "the block the launches went to comes first")
        let quiet = blocks(one, counts: ["a": 9]).filter { $0.kind != .recent }.map(\.kind)
        XCTAssertEqual(quiet, [.category(.music), .category(.games)])
    }

    func testTwoQuickMovesOfOneAppLoseNoWriteAndTheStaleOneIsRefusedOrApplied() throws {
        let dir = scratchDirectory("moved-twice")
        let e = engine(dir)
        _ = e.read(reason: .refresh)
        _ = try XCTUnwrap(e.apply(.setCategory("a", .category(.games))))
        let after = file(dir)
        XCTAssertNotNil(after, "subject: the first move wrote")
        XCTAssertNil(e.apply(.setCategory("a", .category(.games))), "the same move twice: the second changes nothing, so it is refused")
        XCTAssertEqual(file(dir), after, "and writes no byte")
        let other = try XCTUnwrap(e.apply(.setCategory("a", .category(.weather))), "a different target from a stale menu still lands")
        XCTAssertEqual(other.layout.categoryOverrides, ["a": .category(.weather)], "the last one wins, one entry")
        XCTAssertNil(e.apply(.setCategory("a", .category(.music))).flatMap { $0.layout.categoryOverrides["a"] }, "the own category takes it away")
        XCTAssertNil(e.apply(.setCategory("a", nil)), "a stale 'own category' after that is refused")
        XCTAssertFalse(String(decoding: try XCTUnwrap(file(dir)), as: UTF8.self).contains("moved"))
    }

    func testAHandEditedMoveOntoTheAppsOwnCategoryIsHarmlessAndTakenAwayByAnEdit() throws {
        let dir = scratchDirectory("moved-own-by-hand")
        try Data(#"{"version":1,"items":[{"app":"a"},{"app":"b"},{"app":"c"},{"app":"d"}],"moved":{"a":"music","d":"others"}}"#.utf8)
            .write(to: dir.appendingPathComponent("layout.json"))
        let e = engine(dir)
        let read = e.read(reason: .refresh)
        XCTAssertEqual(read.layout.categoryOverrides, ["a": .category(.music), "d": .others], "subject: both are read and counted")
        XCTAssertEqual(ids(.category(.music), read)?.sorted(), ["a", "b", "c"], "harmless: a is where it was")
        XCTAssertEqual(ids(.others, read), ["d"])
        let own = try XCTUnwrap(e.apply(.setCategory("a", .category(.music))), "choosing the own category removes the odd entry")
        XCTAssertEqual(own.layout.categoryOverrides, ["d": .others])
        let none = try XCTUnwrap(e.apply(.returnAllToOwnCategory))
        XCTAssertEqual(none.layout.categoryOverrides, [:])
    }

    func testAnIncompleteReadThenAnEditKeepsTheMoveAndTheNextCompleteReadWithoutTheAppPrunesIt() throws {
        let dir = scratchDirectory("moved-incomplete-edit")
        _ = try { () -> LaunchpadSnapshot in
            let e = engine(dir)
            _ = e.read(reason: .refresh)
            return try XCTUnwrap(e.apply(.setCategory("d", .category(.games))))
        }()
        let partial = engine(dir, catalog(["a", "b", "c"], complete: false))
        XCTAssertEqual(partial.read(reason: .refresh).layout.categoryOverrides, ["d": .category(.games)])
        let edited = try XCTUnwrap(partial.apply(.hide("a")), "an edit on an incomplete read")
        XCTAssertEqual(edited.layout.categoryOverrides, ["d": .category(.games)], "keeps the absent app's move")
        XCTAssertTrue(String(decoding: try XCTUnwrap(file(dir)), as: UTF8.self).contains(#""moved":{"d":"games"}"#), "in the file too")
        XCTAssertNil(partial.apply(.setCategory("d", .others)), "but a move of an app the read does not find is refused")
        XCTAssertEqual(engine(dir, catalog(["a", "b", "c"])).read(reason: .refresh).layout.categoryOverrides, [:], "pruned only by the complete read")
    }

    func testAResetArrangementWithAMoveInTheFileReadsAgainWithTheMoveAndTheDefaultOrder() throws {
        let dir = scratchDirectory("moved-reset-read")
        let e = engine(dir)
        _ = e.read(reason: .refresh)
        _ = try XCTUnwrap(e.apply(.setCategory("c", .others)))
        _ = try XCTUnwrap(e.apply(.move("c", toIndex: 0)))
        let reset = try XCTUnwrap(e.apply(.resetArrangement))
        XCTAssertEqual(reset.layout.categoryOverrides, ["c": .others])
        let fresh = engine(dir).read(reason: .refresh)
        XCTAssertEqual(fresh.layout.categoryOverrides, ["c": .others])
        XCTAssertEqual(fresh.layout.items, reset.layout.items)
        XCTAssertEqual(ids(.others, fresh)?.sorted(), ["c", "d"])
    }
}
