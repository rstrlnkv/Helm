import HelmRuntime
import HelmUI
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The window states pass 15 did not feed: an app in a grid folder moved and then seen in the category view, "Return all" while a
/// card is open, the move's animation flag after a move the engine will refuse, the model's one edit behind the settings row, and
/// the menu's twenty-nine choices (distinct titles, sorted in every language, Others last).
@MainActor final class AMoveUntriedStatesTests: XCTestCase {
    private let music = "public.app-category.music", weather = "public.app-category.weather"
    private let folder = UUID()

    private func armed(_ s: LaunchpadScreenState) -> Bool? {
        Mirror(reflecting: s).children.first { $0.label == "animateNextUpdate" }?.value as? Bool
    }

    private func rig() -> LiftRig {
        let rig = LiftRig(self, apps: ["a", "b", "c", "d"],
                          layout: LaunchpadLayout(items: [.folder(.init(id: folder, name: "F", apps: ["a", "b"])), .app("c"), .app("d")]))
        rig.categorize(["a": music, "b": music, "c": music, "d": weather])
        rig.state.onMove = { [unowned rig] id, target in
            if let landed = rig.engine.apply(.setCategory(id, target)) { rig.state.update(snapshot: landed) }
        }
        return rig
    }

    private func block(_ kind: LaunchpadCategoryBlock.Kind) -> UUID { LaunchpadCategoryBlock(kind: kind, apps: [], launches: 0).id }

    func testAnAppInAGridFolderMovedIsInTheNewBlockAndTheFolderKeepsItsPlaceInTheGrid() throws {
        let rig = rig()
        XCTAssertEqual(rig.ids(), [folder.uuidString, "c", "d"], "subject: the grid has the folder holding a and b")
        rig.state.move("a", to: .category(.weather))
        XCTAssertEqual(rig.ids(), [folder.uuidString, "c", "d"], "the grid is as it was")
        guard case .folder(_, _, let held, _) = rig.state.pages[0][0] else { return XCTFail("folder") }
        XCTAssertEqual(held.map(\.id), ["a", "b"], "a is in its folder still")
        rig.state.setView(.categories)
        XCTAssertEqual(rig.ids(), [block(.category(.music)), block(.category(.weather)), LaunchpadHiddenBlock.id].map(\.uuidString))
        rig.state.open(folder: block(.category(.weather)))
        XCTAssertEqual(Set(rig.state.folderApps.map(\.id)), ["a", "d"])
        rig.state.open(folder: block(.category(.music)))
        XCTAssertEqual(Set(rig.state.folderApps.map(\.id)), ["b", "c"], "and not in Music")
    }

    func testReturnAllWhileACardIsOpenMovesTheAppsBackAndTheCardStaysOnItsBlock() throws {
        let rig = rig()
        rig.state.setView(.categories)
        rig.state.move("a", to: .category(.weather))
        rig.state.move("b", to: .category(.weather))
        let weatherID = block(.category(.weather))
        rig.state.open(folder: weatherID)
        XCTAssertEqual(Set(rig.state.folderApps.map(\.id)), ["a", "b", "d"], "subject: the card shows the moved apps")
        let landed = try XCTUnwrap(rig.engine.apply(.returnAllToOwnCategory))
        rig.state.update(snapshot: landed)
        XCTAssertEqual(rig.state.moved, [:])
        XCTAssertEqual(rig.state.openFolder, weatherID, "the card is still on its block")
        XCTAssertEqual(rig.state.folderApps.map(\.id), ["d"])
        XCTAssertTrue(rig.ids().contains(block(.category(.music)).uuidString))
    }

    func testAMoveIsArmedOnlyInTheCategoryViewAndTheNextUpdateSpendsIt() {
        let rig = rig()
        rig.state.onMove = nil
        rig.state.move("a", to: .others)
        XCTAssertEqual(armed(rig.state), false, "in the grid nothing visible moves, so nothing is armed")
        rig.state.setView(.categories)
        XCTAssertEqual(armed(rig.state), false, "subject: readable and off")
        rig.state.move("a", to: .others)
        XCTAssertEqual(armed(rig.state), true)
        rig.state.update(snapshot: rig.engine.read(reason: .refresh))
        XCTAssertEqual(armed(rig.state), false, "spent by the next update, answer or not")
    }

    func testAMoveTheEngineWillRefuseDoesNotLeaveTheFlagForALaterUpdate() throws {
        let rig = rig()
        rig.state.setView(.categories)
        rig.state.move("a", to: .others)
        XCTAssertEqual(rig.state.moved, ["a": .others], "subject: a is moved")
        XCTAssertEqual(armed(rig.state), false, "the answer spent it")
        rig.state.move("a", to: .others)
        XCTAssertEqual(armed(rig.state), false, "a stale menu asks for what is so: the engine refuses, no update comes, and the flag must not wait for an unrelated one")
        rig.state.move("c", to: nil)
        XCTAssertEqual(armed(rig.state), false, "returning an app that is not moved: the same")
    }

    func testTheModelsReturnAllIsOneEditAndAnotherAtZeroChangesNothing() async throws {
        let dir = scratchDirectory("moved-model")
        let engine = LaunchpadEngine(catalog: RigCatalog(["a", "b"]), launcher: RigLauncher(), store: LayoutStore(directory: dir))
        let model = LaunchpadViewModel(work: engine, store: NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore()))
        let shown = Task { await model.whileShown() }
        defer { shown.cancel() }
        for _ in 0..<500 where model.snapshot == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.snapshot?.layout.categoryOverrides, [:], "the control: nothing moved, so the row says 0 and the button is off")
        await model.moveToCategory("a", to: .category(.games))
        await model.moveToCategory("b", to: .category(.music))
        XCTAssertEqual(model.snapshot?.layout.categoryOverrides.count, 2, "the row says 2")
        await model.returnAllMoved()
        XCTAssertEqual(model.snapshot?.layout.categoryOverrides, [:])
        let file = dir.appendingPathComponent("layout.json")
        let after = try Data(contentsOf: file)
        XCTAssertFalse(String(decoding: after, as: UTF8.self).contains("moved"))
        await model.returnAllMoved()
        XCTAssertEqual(try Data(contentsOf: file), after, "a second press at zero writes nothing")
        XCTAssertNil(model.notice)
    }

    func testTheChoicesAreTwentyNineDistinctTitlesSortedInEveryLanguageOthersLast() {
        AppLanguage.each { language in
            let choices = LaunchpadCategoryName.choices(language: language)
            XCTAssertEqual(choices.count, 29, "\(language)")
            XCTAssertEqual(Set(choices.map(\.title)).count, 29, "\(language): every title differs")
            XCTAssertEqual(Set(choices.map(\.target)).count, 29, "\(language)")
            XCTAssertEqual(choices.last?.target, .others, "\(language): Others is last, whatever its title sorts as")
            XCTAssertEqual(choices.last?.title, LaunchpadCategoryName.title(for: .others, language: language))
            let first = choices.dropLast().map(\.title)
            XCTAssertEqual(first, first.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "\(language): the 28 are sorted")
            for utility in [LaunchpadCategory.utilities, .video] {
                XCTAssertEqual(choices.first { $0.target == .category(utility) }?.title, LaunchpadCategoryName.name(of: utility, language: language))
            }
            XCTAssertEqual(choices.first { $0.target == .category(.utilities) }?.title, HelmWord.utilities(language: language), "\(language): from the kit")
            XCTAssertEqual(choices.first { $0.target == .category(.video) }?.title, HelmWord.video(language: language), "\(language): from the kit")
        }
    }
}
