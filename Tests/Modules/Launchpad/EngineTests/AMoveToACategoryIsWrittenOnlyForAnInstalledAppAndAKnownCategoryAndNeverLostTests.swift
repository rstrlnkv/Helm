import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// A move to a category is one entry in the layout file under `moved`: written only for an app the read finds and for a
/// category other than its own, carried by every edit but the ones that give it back (`.setCategory(id, nil)`, `.returnAllToOwnCategory`, the own-category
/// collapse) and by Reset arrangement, dropped by a complete read that does not find the app (never by an incomplete one), and absent from a file that holds no move.
final class AMoveToACategoryIsWrittenOnlyForAnInstalledAppAndAKnownCategoryAndNeverLostTests: XCTestCase {
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

    /// "d" (no category of its own) is moved to Games.
    private func moved(_ e: LaunchpadEngine) throws -> LaunchpadSnapshot {
        _ = e.read()
        let snap = try XCTUnwrap(e.apply(.setCategory("d", .category(.games))))
        XCTAssertEqual(snap.layout.categoryOverrides, ["d": .category(.games)], "subject: the move was made")
        return snap
    }

    func testAMoveSurvivesASaveAFreshStoreAndAFreshEngine() throws {
        let dir = scratchDirectory("moved-roundtrip")
        _ = try moved(engine(dir))
        XCTAssertTrue(String(decoding: try XCTUnwrap(file(dir)), as: UTF8.self).contains(#""moved":{"d":"games"}"#))
        XCTAssertEqual(engine(dir).read().layout.categoryOverrides, ["d": .category(.games)])
        _ = try XCTUnwrap(engine(dir).apply(.setCategory("a", .others)))
        XCTAssertEqual(engine(dir).read().layout.categoryOverrides, ["d": .category(.games), "a": .others])
    }

    func testAnUninstalledAppIsRefusedAndTheFileIsNotTouched() throws {
        let dir = scratchDirectory("moved-gone")
        let e = engine(dir)
        _ = try moved(e)
        let before = file(dir)
        XCTAssertNotNil(before, "subject: the file was written")
        XCTAssertNil(e.apply(.setCategory("nobody", .category(.games))))
        XCTAssertNil(e.apply(.setCategory("nobody", nil)))
        XCTAssertEqual(file(dir), before)
    }

    func testAMoveToTheAppsOwnCategoryStoresNothingAndTakesAnEarlierMoveAway() throws {
        let dir = scratchDirectory("moved-own")
        let e = engine(dir)
        _ = e.read()
        XCTAssertNil(e.apply(.setCategory("a", .category(.music))), "own category, nothing moved: nothing to write")
        XCTAssertNil(file(dir))
        XCTAssertNil(e.apply(.setCategory("d", .others)), "d's own is Others (it declares none)")
        _ = try XCTUnwrap(e.apply(.setCategory("a", .category(.games))))
        let back = try XCTUnwrap(e.apply(.setCategory("a", .category(.music))))
        XCTAssertEqual(back.layout.categoryOverrides, [:])
        XCTAssertFalse(String(decoding: try XCTUnwrap(file(dir)), as: UTF8.self).contains("moved"))
    }

    func testEveryEditAndAResetKeepTheMove() throws {
        let e = engine(scratchDirectory("moved-edits"))
        _ = try moved(e)
        let made = try XCTUnwrap(e.apply(.makeFolder(drop: "b", onto: "a", name: "F")))
        guard case .folder(let f) = try XCTUnwrap(made.layout.items.first) else { return XCTFail("no folder") }
        for edit: LaunchpadEdit in [.rename(f.id, to: "G"), .resize(f.id, large: true), .place("d", relativeTo: "c", after: false),
                                    .move("d", toIndex: 0), .newPage(moving: "d"), .hide("d"), .unhide("d"), .hide("c"),
                                    .resetArrangement, .setCategory("a", .others)] {
            let snap = try XCTUnwrap(e.apply(edit), "\(edit)")
            XCTAssertEqual(snap.layout.categoryOverrides["d"], .category(.games), "\(edit)")
        }
    }

    func testAResetArrangementKeepsTheMoveInTheFileToo() throws {
        let dir = scratchDirectory("moved-reset")
        let e = engine(dir)
        _ = try moved(e)
        _ = try XCTUnwrap(e.apply(.resetArrangement))
        XCTAssertEqual(engine(dir).read().layout.categoryOverrides, ["d": .category(.games)])
    }

    func testACompleteReadThatLacksTheAppDropsItsMoveAndAnIncompleteOneKeepsIt() throws {
        let dir = scratchDirectory("moved-prune")
        _ = try moved(engine(dir))
        XCTAssertEqual(engine(dir, catalog(["a", "b", "c", "d"])).read().layout.categoryOverrides, ["d": .category(.games)],
                       "still installed: kept")
        XCTAssertEqual(engine(dir, catalog(["a", "b", "c"], complete: false)).read().layout.categoryOverrides, ["d": .category(.games)],
                       "an unreadable folder looks like an uninstalled app: kept")
        XCTAssertEqual(engine(dir, catalog(["a", "b", "c"])).read().layout.categoryOverrides, [:], "gone on a complete read")
        XCTAssertNotNil(file(dir).flatMap { String(decoding: $0, as: UTF8.self).range(of: "games") }, "and a read writes nothing")
    }

    func testReturnAllEmptiesTheMovesAndTheFileHasNoKey() throws {
        let dir = scratchDirectory("moved-all")
        let e = engine(dir)
        _ = try moved(e)
        _ = try XCTUnwrap(e.apply(.setCategory("a", .others)))
        let none = try XCTUnwrap(e.apply(.returnAllToOwnCategory))
        XCTAssertEqual(none.layout.categoryOverrides, [:])
        XCTAssertFalse(String(decoding: try XCTUnwrap(file(dir)), as: UTF8.self).contains("moved"))
        XCTAssertNil(e.apply(.returnAllToOwnCategory), "nothing moved: refused")
    }

    func testAFileWithoutMovesIsAsItWasAndTheVersionIsOne() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = String(decoding: try encoder.encode(LaunchpadLayout(items: [.app("a")], hidden: ["h"])), as: UTF8.self)
        XCTAssertEqual(text, #"{"hidden":["h"],"items":[{"app":"a"}],"version":1}"#)
        let with = String(decoding: try encoder.encode(LaunchpadLayout(items: [.app("a")], hidden: [], categoryOverrides: ["b": .others])), as: UTF8.self)
        XCTAssertEqual(with, #"{"hidden":[],"items":[{"app":"a"}],"moved":{"b":"others"},"version":1}"#)
    }
}
