import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A moved app is in the block it was sent to and in no other (Recently Added by its date apart), a hidden app in none, its launches
/// go with it; an open card of the block it left keeps working and the card of a block the move emptied closes; and a move
/// changes nothing the grid draws; the menu offers the undo only for a moved app and checks the category the app is in. Each case first proves the block or page it asserts about is there.
@MainActor final class AMoveShowsInTheRightBlockAndNothingInTheGridChangesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func app(_ id: String, _ category: String?, added: Date? = nil) -> CatalogApp {
        CatalogApp(id: id, name: id, path: "/Applications/\(id).app", category: category.map { "public.app-category.\($0)" }, added: added)
    }

    private func blocks(_ apps: [CatalogApp], hidden: Set<String> = [], counts: [String: Int] = [:],
                        overrides: [String: LaunchpadCategoryTarget] = [:]) -> [LaunchpadCategoryBlock] {
        LaunchpadCategories.blocks(apps: apps, hidden: hidden, counts: counts, now: now, overrides: overrides) { kind in
            switch kind {
            case .recent: "Recently Added"
            case .others: "Others"
            case .category(let c): c.rawValue
            }
        }
    }

    private func ids(_ kind: LaunchpadCategoryBlock.Kind, in all: [LaunchpadCategoryBlock]) -> [String]? {
        all.first { $0.kind == kind }?.apps.map(\.id)
    }

    private var catalog: [CatalogApp] {
        [app("a", "music", added: now.addingTimeInterval(-86_400)), app("b", "music"), app("c", "weather"), app("d", nil)]
    }

    func testAMovedAppIsInTheTargetBlockOnlyAndInRecentlyAddedByItsDate() {
        let before = blocks(catalog)
        XCTAssertEqual(ids(.category(.music), in: before), ["a", "b"], "the control: a is in Music before the move")
        XCTAssertEqual(ids(.recent, in: before), ["a"])
        let after = blocks(catalog, overrides: ["a": .category(.weather)])
        XCTAssertEqual(ids(.category(.music), in: after), ["b"])
        XCTAssertEqual(ids(.category(.weather), in: after), ["a", "c"])
        XCTAssertNil(ids(.others, in: after)?.first { $0 == "a" })
        XCTAssertEqual(ids(.recent, in: after), ["a"], "the move is not the date")
        XCTAssertEqual(after.flatMap(\.apps).filter { $0.id == "a" }.count, 2, "once in a category block, once in Recently Added")
    }

    func testAMoveToOthersWorksAndABlockItEmptiesIsGone() {
        let toOthers = blocks(catalog, overrides: ["b": .others])
        XCTAssertEqual(ids(.others, in: toOthers), ["b", "d"])
        let emptied = blocks(catalog, overrides: ["c": .category(.music)])
        XCTAssertEqual(ids(.category(.music), in: emptied)?.sorted(), ["a", "b", "c"], "the control: c arrived")
        XCTAssertNil(ids(.category(.weather), in: emptied), "its own block has nobody left, so it is not made")
    }

    func testAHiddenAppStaysInNoBlockAndTheCountsGoWithTheApp() {
        let hidden = blocks(catalog, hidden: ["a"], overrides: ["a": .category(.weather)])
        XCTAssertEqual(ids(.category(.weather), in: hidden), ["c"], "the control: the weather block exists")
        XCTAssertFalse(hidden.flatMap(\.apps).contains { $0.id == "a" })
        let counts = ["a": 10, "c": 1, "b": 2]
        let before = blocks(catalog, counts: counts)
        XCTAssertEqual(before.first { $0.kind == .category(.music) }?.launches, 12, "the control: Music counts a and b")
        let after = blocks(catalog, counts: counts, overrides: ["a": .category(.weather)])
        XCTAssertEqual(after.first { $0.kind == .category(.weather) }?.launches, 11)
        XCTAssertEqual(after.first { $0.kind == .category(.music) }?.launches, 2)
        XCTAssertEqual(after.first { $0.kind != .recent }?.kind, .category(.weather), "the block that took the launches goes first")
    }

    // MARK: - The window's state

    private func rig() -> LiftRig {
        let rig = LiftRig(self, apps: ["a", "b", "c", "d", "e"])
        rig.categorize(["a": "public.app-category.music", "b": "public.app-category.music", "c": "public.app-category.music",
                        "d": "public.app-category.weather"])
        rig.state.onMove = { [unowned rig] id, target in
            if let landed = rig.engine.apply(.setCategory(id, target)) { rig.state.update(snapshot: landed) }
        }
        return rig
    }

    func testAnOpenCardOfTheBlockTheAppLeftKeepsWorkingAndTheCardOfAnEmptiedBlockCloses() throws {
        let rig = rig()
        rig.state.setView(.categories)
        let music = LaunchpadCategoryBlock(kind: .category(.music), apps: [], launches: 0).id
        let weather = LaunchpadCategoryBlock(kind: .category(.weather), apps: [], launches: 0).id
        let others = LaunchpadCategoryBlock(kind: .others, apps: [], launches: 0).id
        XCTAssertEqual(rig.ids(), [music, weather, others].map(\.uuidString), "the control: three blocks")
        rig.state.open(folder: music)
        XCTAssertEqual(rig.state.folderApps.map(\.id), ["a", "b", "c"])
        rig.state.move("a", to: .category(.weather))
        XCTAssertEqual(rig.state.openFolder, music, "the card of the block the app left stays open")
        XCTAssertEqual(rig.state.folderApps.map(\.id), ["b", "c"])
        rig.state.closeFolder()

        rig.state.open(folder: weather)
        XCTAssertEqual(rig.state.folderApps.map(\.id), ["a", "d"], "the control: a arrived in Weather")
        rig.state.move("a", to: nil)
        rig.state.move("d", to: .category(.music))
        XCTAssertEqual(rig.state.folderApps.map(\.id), [], "no app is left in Weather")
        XCTAssertNil(rig.state.openFolder, "the card of a block the move emptied is closed")
        XCTAssertFalse(rig.ids().contains(weather.uuidString))
    }

    func testAMoveInTheGridChangesNoPageAndTheStateFollowsTheSnapshot() throws {
        let rig = rig()
        let pages = rig.ids(), page = rig.state.page
        XCTAssertEqual(pages, ["a", "b", "c", "d", "e"], "the control: the grid shows every app")
        XCTAssertEqual(rig.state.moved, [:])
        rig.state.move("a", to: .others)
        rig.state.move("d", to: .category(.music))
        XCTAssertEqual(rig.state.moved, ["a": .others, "d": .category(.music)], "subject: the moves landed")
        XCTAssertEqual(rig.ids(), pages)
        XCTAssertEqual(rig.state.page, page)
        rig.state.move("a", to: nil)
        XCTAssertEqual(rig.state.moved, ["d": .category(.music)])
        rig.state.setView(.categories)
        XCTAssertEqual(rig.state.moved, ["d": .category(.music)], "the category view reads the same moves")
    }

    func testTheMenuOffersTheUndoOnlyForAMovedAppAndChecksTheEffectiveCategory() {
        XCTAssertFalse(LaunchpadAppMenu.canReturn(moved: nil))
        XCTAssertTrue(LaunchpadAppMenu.canReturn(moved: .others))
        XCTAssertEqual(LaunchpadAppMenu.effective(moved: nil, raw: "public.app-category.music"), .category(.music))
        XCTAssertEqual(LaunchpadAppMenu.effective(moved: nil, raw: nil), .others)
        XCTAssertEqual(LaunchpadAppMenu.effective(moved: .category(.games), raw: "public.app-category.music"), .category(.games))
    }
}
