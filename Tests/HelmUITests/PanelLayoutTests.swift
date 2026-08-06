import XCTest
@testable import HelmUI

/// What the panel remembers, and what it must never forget by accident.
final class PanelLayoutTests: XCTestCase {

    private func layout(_ widgets: [(String, PanelWidgetSize)]) -> PanelLayout {
        PanelLayout(tabs: [.init(id: "t", seed: "main", name: nil,
                                 widgets: widgets.map { .init(widget: $0.0, size: $0.1) })])
    }

    // MARK: - Seeding

    /// A fresh install gets the panel it had before there was a layout: one
    /// tab, everything at full width, in the order the person arranged.
    func testTheSeedIsTodaysPanel() {
        let seeded = PanelLayout.seeded(from: ["keepawake", "vpn", "disk"])
        XCTAssertEqual(seeded.tabs.count, 1)
        XCTAssertEqual(seeded.allSlots.map(\.widget), ["keepawake", "vpn", "disk"])
        XCTAssertEqual(Set(seeded.allSlots.map(\.size)), [.wide])
    }

    // MARK: - Reconciling

    /// A module that arrived with this update appears the first time the panel
    /// is opened, not after somebody happens to rearrange something.
    func testANewModuleArrivesAtTheEndOfTheFirstTab() {
        let before = layout([("vpn", .compact)])
        let after = before.reconciled(arriving: ["vpn", "homebrew"])
        XCTAssertEqual(after.allSlots.map(\.widget), ["vpn", "homebrew"])
        XCTAssertEqual(after.allSlots.last?.size, .wide)
    }

    /// Nothing is moved or resized to make room for it.
    func testArrivingLeavesEverythingElseAlone() {
        let before = layout([("vpn", .compact), ("disk", .tall)])
        let after = before.reconciled(arriving: ["vpn", "disk", "homebrew"])
        XCTAssertEqual(after.allSlots.prefix(2).map(\.size), [.compact, .tall])
    }

    /// **The rule that differs from the sidebar's.** A widget this build cannot
    /// draw stays in the layout: it is a module switched off, or one a
    /// downgrade took away. Dropping it here would let an update empty
    /// somebody's panel, and the next save would make that permanent.
    func testAWidgetThisBuildCannotDrawKeepsItsPlace() {
        let before = layout([("vpn", .compact), ("from.the.future", .tall), ("disk", .wide)])
        let after = before.reconciled(arriving: ["vpn", "disk"])
        XCTAssertEqual(after.allSlots.map(\.widget), ["vpn", "from.the.future", "disk"])
    }

    /// A half-written save is reachable, and a widget held twice would draw
    /// twice. The first placement is the one that survives.
    func testAWidgetHeldTwiceCollapsesToItsFirstPlacement() {
        let doubled = PanelLayout(tabs: [
            .init(id: "a", widgets: [.init(widget: "vpn", size: .compact)]),
            .init(id: "b", widgets: [.init(widget: "vpn", size: .tall)]),
        ])
        let after = doubled.reconciled(arriving: ["vpn"])
        XCTAssertEqual(after.allSlots.map(\.widget), ["vpn"])
        XCTAssertEqual(after.allSlots.first?.size, .compact)
    }

    /// A layout with no tabs at all — corrupt, or hand-edited — gets one, or
    /// there is nowhere for an arriving module to go.
    func testALayoutWithNoTabsGetsOne() {
        let after = PanelLayout(tabs: []).reconciled(arriving: ["vpn"])
        XCTAssertEqual(after.tabs.count, 1)
        XCTAssertEqual(after.allSlots.map(\.widget), ["vpn"])
    }

    /// The control. Every assertion above passes on a `reconciled` that returns
    /// the seed, and this is the one that does not.
    func testReconcilingIsNotJustReseeding() {
        let before = layout([("disk", .tall), ("vpn", .compact)])
        let after = before.reconciled(arriving: ["vpn", "disk"])
        XCTAssertEqual(after.allSlots.map(\.widget), ["disk", "vpn"],
                       "the person's order was replaced by the offered order")
        XCTAssertNotEqual(after, PanelLayout.seeded(from: ["vpn", "disk"]))
    }

    // MARK: - Storage

    func testALayoutSurvivesTheRoundTrip() {
        let before = layout([("vpn", .compact), ("disk", .tall)])
        let data = try! JSONEncoder().encode(before)
        XCTAssertEqual(try! JSONDecoder().decode(PanelLayout.self, from: data), before)
    }

    /// A size written by a newer build reads as `wide` rather than throwing.
    ///
    /// Synthesised `Decodable` throws on an unknown raw value and `JSONDecoder`
    /// gives up on the whole document — so one slot from a newer build would
    /// empty the entire panel, and the next save would write that emptiness
    /// down. A downgrade should cost a widget's proportions, not the
    /// arrangement.
    func testASizeFromTheFutureDoesNotTakeTheLayoutWithIt() throws {
        let json = """
        {"tabs":[{"id":"t","widgets":[
          {"widget":"vpn","size":"enormous"},
          {"widget":"disk","size":"compact"}]}]}
        """
        let decoded = try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.allSlots.map(\.widget), ["vpn", "disk"])
        XCTAssertEqual(decoded.allSlots.map(\.size), [.wide, .compact])
    }

    /// The control for that one: a *known* size still decodes as itself, so the
    /// lenient path is not quietly answering `wide` to everything.
    func testAKnownSizeStillDecodesAsItself() throws {
        let json = """
        {"tabs":[{"id":"t","widgets":[{"widget":"vpn","size":"tall"}]}]}
        """
        let decoded = try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.allSlots.first?.size, .tall)
    }

    // MARK: - Rearranging

    func testMovingWithinATabDoesNotLeaveACopy() {
        let before = layout([("a", .wide), ("b", .wide), ("c", .wide)])
        let after = before.moving("c", toTab: 0, at: 0)
        XCTAssertEqual(after.allSlots.map(\.widget), ["c", "a", "b"])
    }

    func testMovingBetweenTabsTakesTheSizeWithIt() {
        let before = PanelLayout(tabs: [
            .init(id: "a", widgets: [.init(widget: "vpn", size: .tall)]),
            .init(id: "b", widgets: []),
        ])
        let after = before.moving("vpn", toTab: 1, at: 0)
        XCTAssertEqual(after.tabs[0].widgets.count, 0)
        XCTAssertEqual(after.tabs[1].widgets.first?.size, .tall)
    }

    /// An index past the end lands at the end rather than trapping.
    func testAnIndexPastTheEndIsTheEnd() {
        let before = layout([("a", .wide), ("b", .wide)])
        XCTAssertEqual(before.moving("a", toTab: 0, at: 99).allSlots.map(\.widget), ["b", "a"])
    }

    // MARK: - Sizes, and the one refusal

    /// Only a full-width widget may grow downwards: a tall narrow one opens a
    /// hole beside it that nothing fills without masonry.
    func testACompactWidgetIsRefusedTall() {
        let before = layout([("vpn", .compact)])
        XCTAssertEqual(before.refusal(growing: "vpn", to: .tall), .tallNeedsFullWidth)
        XCTAssertEqual(before.resizing("vpn", to: .tall).allSlots.first?.size, .compact)
    }

    /// And the way through it — the refusal has something to say, which is why
    /// it is a refusal rather than a greyed button.
    func testGoingThroughWideIsAllowed() {
        var l = layout([("vpn", .compact)])
        l = l.resizing("vpn", to: .wide)
        XCTAssertNil(l.refusal(growing: "vpn", to: .tall))
        XCTAssertEqual(l.resizing("vpn", to: .tall).allSlots.first?.size, .tall)
    }

    /// The control: everything else is allowed, so the refusal is about the one
    /// case and not about resizing in general.
    func testEveryOtherSizeChangeIsAllowed() {
        for from: PanelWidgetSize in PanelWidgetSize.allCases {
            for to: PanelWidgetSize in PanelWidgetSize.allCases where !(from == .compact && to == .tall) {
                let l = layout([("vpn", from)])
                XCTAssertNil(l.refusal(growing: "vpn", to: to), "\(from) → \(to) was refused")
                XCTAssertEqual(l.resizing("vpn", to: to).allSlots.first?.size, to)
            }
        }
    }

    // MARK: - Adding and removing

    func testRemovingTakesOnlyThatWidget() {
        let after = layout([("a", .wide), ("b", .compact)]).removing("a")
        XCTAssertEqual(after.allSlots.map(\.widget), ["b"])
    }

    /// A widget already in the panel is moved, not copied — the gallery only
    /// offers what is missing, but a layout that could hold two of one thing
    /// would draw it twice.
    func testAddingSomethingAlreadyThereMovesIt() {
        let after = layout([("a", .compact), ("b", .wide)]).adding("a", toTab: 0)
        XCTAssertEqual(after.allSlots.map(\.widget), ["b", "a"])
    }

    func testAddingArrivesAtFullWidth() {
        let after = layout([]).adding("vpn", toTab: 0)
        XCTAssertEqual(after.allSlots.first?.size, .wide)
    }

    /// The control for all of the above: a mutation that finds nothing to move
    /// returns the layout it was given, rather than an empty one.
    ///
    /// `removing` is not among them, and deliberately. It stopped being «take
    /// this slot out» and became «this is not a tile», which is a statement
    /// worth recording whether or not there was a slot to take out — a module
    /// in the drawer has no slot and can still be refused a tile.
    func testAMutationThatMatchesNothingChangesNothing() {
        let before = layout([("a", .wide)])
        XCTAssertEqual(before.resizing("nope", to: .tall), before)
        XCTAssertEqual(before.moving("nope", toTab: 0, at: 0), before)
        XCTAssertEqual(before.adding("a", toTab: 7), before)
    }

    // MARK: - Tabs

    /// The strip is worth its row only once there is a second tab.
    func testOneTabShowsNoStrip() {
        XCTAssertFalse(layout([("a", .wide)]).showsTabBar)
        XCTAssertTrue(layout([("a", .wide)]).addingTab(id: "t2").showsTabBar)
    }

    /// Closing a tab hands its widgets to the neighbour rather than dropping
    /// them: somebody arranged those, and taking six widgets with the tab is a
    /// second and larger action nobody asked for.
    func testClosingATabHandsItsWidgetsToTheNeighbour() {
        let before = PanelLayout(tabs: [
            .init(id: "a", widgets: [.init(widget: "vpn", size: .wide)]),
            .init(id: "b", widgets: [.init(widget: "disk", size: .compact)]),
        ])
        let after = before.removingTab("b")
        XCTAssertEqual(after.tabs.count, 1)
        XCTAssertEqual(after.allSlots.map(\.widget), ["vpn", "disk"])
    }

    /// Closing the first hands them to the right, which is the tab about to be
    /// looked at.
    func testClosingTheFirstTabHandsThemRight() {
        let before = PanelLayout(tabs: [
            .init(id: "a", widgets: [.init(widget: "vpn", size: .wide)]),
            .init(id: "b", widgets: [.init(widget: "disk", size: .compact)]),
        ])
        let after = before.removingTab("a")
        XCTAssertEqual(after.allSlots.map(\.widget), ["disk", "vpn"])
    }

    /// The last tab cannot be closed: a panel with no tabs has nowhere to put
    /// anything, and `reconciled` would have to invent one back.
    func testTheLastTabCannotBeClosed() {
        let only = layout([("vpn", .wide)])
        XCTAssertEqual(only.removingTab("t"), only)
    }

    /// An empty name is not a name — it is the default, asked for again.
    func testAnEmptyNameIsTheDefaultName() {
        let named = layout([]).renamingTab("t", to: "Работа")
        XCTAssertEqual(named.tabs[0].name, "Работа")
        XCTAssertNil(named.renamingTab("t", to: "   ").tabs[0].name)
    }

    /// The control: renaming and closing find their tab by id, and a call that
    /// names none changes nothing.
    func testATabCallThatMatchesNothingChangesNothing() {
        let before = layout([("vpn", .wide)])
        XCTAssertEqual(before.renamingTab("nope", to: "x"), before)
        XCTAssertEqual(before.removingTab("nope"), before)
    }

    // MARK: - A widget that was taken off stays off

    /// The bug this was written for: removing a widget was undone by the next
    /// read. `reconciled` adds any id this build can draw that the layout does
    /// not hold — which is how a new module joins — and a widget just removed
    /// is exactly that. It came back at every launch.
    func testARemovedWidgetDoesNotComeBackOnTheNextRead() {
        let after = layout([("vpn", .wide), ("disk", .wide)])
            .removing("disk")
            .reconciled(arriving: ["vpn", "disk"])
        XCTAssertEqual(after.allSlots.map(\.widget), ["vpn"])
    }

    /// And it does not come back on the tenth read either — the note is part
    /// of what gets written, not something recomputed from what is on screen.
    func testItStaysOffAcrossManyReads() {
        var l = layout([("vpn", .wide), ("disk", .wide)]).removing("disk")
        for _ in 0..<10 { l = l.reconciled(arriving: ["vpn", "disk"]) }
        XCTAssertEqual(l.allSlots.map(\.widget), ["vpn"])
    }

    /// The control, and the thing that must not break: a module that has
    /// genuinely never been on the panel still arrives.
    func testAModuleNobodyRemovedStillArrives() {
        let after = layout([("vpn", .wide)])
            .removing("vpn")
            .reconciled(arriving: ["vpn", "homebrew"])
        XCTAssertEqual(after.allSlots.map(\.widget), ["homebrew"],
                       "dismissing one widget silenced the others")
    }

    /// Putting it back answers the removal, so an update does not make somebody
    /// add it again.
    func testAddingItBackClearsTheNote() {
        let back = layout([("vpn", .wide)])
            .removing("vpn")
            .adding("vpn", toTab: 0)
        XCTAssertTrue(back.dismissed.isEmpty)
        XCTAssertEqual(back.reconciled(arriving: ["vpn"]).allSlots.map(\.widget), ["vpn"])
    }

    /// A panel arranged before this build has no `dismissed` key, and the
    /// synthesised decoder would have thrown on it — taking the whole layout
    /// with it, because `JSONDecoder` gives up on the document rather than the
    /// field.
    func testALayoutFromBeforeThisBuildStillDecodes() throws {
        let json = """
        {"tabs":[{"id":"t","widgets":[{"widget":"vpn","size":"tall"}]}]}
        """
        let decoded = try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.allSlots.map(\.widget), ["vpn"])
        XCTAssertTrue(decoded.dismissed.isEmpty)
    }

    func testTheNoteSurvivesTheRoundTrip() throws {
        let before = layout([("vpn", .wide), ("disk", .wide)]).removing("disk")
        let data = try JSONEncoder().encode(before)
        XCTAssertEqual(try JSONDecoder().decode(PanelLayout.self, from: data).dismissed, ["disk"])
    }

    // MARK: - Not a tile is not the same as not here

    /// The report that produced this distinction, in one test: «I want to take
    /// the keyboard widget off but keep it in the utilities.» Removing a widget
    /// stops it being a tile and nothing more — the drawer holds everything
    /// that is not one.
    func testTakingAWidgetOffLeavesItInThePanel() {
        let after = layout([("layout", .wide), ("vpn", .wide)]).removing("layout")
        XCTAssertTrue(after.isDismissed("layout"), "it would come back as a tile")
        XCTAssertFalse(after.isHidden("layout"), "it was taken out of the panel entirely")
        XCTAssertEqual(after.allSlots.map(\.widget), ["vpn"])
    }

    /// And the second press, on a row that is already only a row, does mean
    /// «not here».
    func testTheSecondPressTakesItOutOfThePanel() {
        let after = layout([("layout", .wide)]).removing("layout").hiding("layout")
        XCTAssertTrue(after.isHidden("layout"))
    }

    /// Hiding something that was never a tile works the same way: `removing`
    /// no longer needs to find a slot before it can record anything.
    func testAModuleWithNoTileCanBeHidden() {
        let after = layout([("vpn", .wide)]).hiding("homebrew")
        XCTAssertTrue(after.isHidden("homebrew"))
        XCTAssertEqual(after.allSlots.map(\.widget), ["vpn"], "the grid was disturbed")
    }

    /// The gallery puts it back in the panel, not straight into the grid:
    /// where it belongs there is the next decision, taken in the drawer.
    func testRestoringPutsItBackInTheDrawerOnly() {
        let after = layout([]).hiding("homebrew").restoring("homebrew")
        XCTAssertFalse(after.isHidden("homebrew"))
        XCTAssertEqual(after.allSlots.count, 0)
    }

    /// Promoting answers both refusals at once, or a widget added from the
    /// drawer would need adding again after every update.
    func testPromotingClearsBothRefusals() {
        let after = layout([]).removing("layout").hiding("layout").adding("layout", toTab: 0)
        XCTAssertFalse(after.isDismissed("layout"))
        XCTAssertFalse(after.isHidden("layout"))
        XCTAssertEqual(after.allSlots.map(\.widget), ["layout"])
    }

    /// Neither list re-adds a tile on the next read.
    func testNeitherRefusalIsUndoneByAReread() {
        var l = layout([("layout", .wide), ("vpn", .wide)]).removing("layout").hiding("homebrew")
        for _ in 0..<5 { l = l.reconciled(arriving: ["layout", "vpn", "homebrew"]) }
        XCTAssertEqual(l.allSlots.map(\.widget), ["vpn"])
        XCTAssertTrue(l.isHidden("homebrew"))
    }

    /// The control: refusing one thing refuses one thing, and the two lists do
    /// not answer for each other.
    func testTheTwoListsAreNotOneList() {
        let after = layout([("layout", .wide)]).removing("layout")
        XCTAssertFalse(after.isHidden("layout"))
        XCTAssertFalse(after.isDismissed("vpn"))
        let gone = layout([("layout", .wide)]).hiding("layout")
        XCTAssertTrue(gone.isDismissed("layout"), "hidden must also stop being a tile")
    }

    /// A layout written before either list existed still decodes — the
    /// synthesised decoder throws on a missing key and takes the document with
    /// it.
    func testALayoutFromBeforeEitherListDecodes() throws {
        let json = """
        {"tabs":[{"id":"t","widgets":[{"widget":"vpn","size":"wide"}]}]}
        """
        let decoded = try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.dismissed.isEmpty)
        XCTAssertTrue(decoded.hidden.isEmpty)
    }
}
