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

    /// The control for all of the above: a mutation that finds nothing to do
    /// returns the layout it was given, rather than an empty one.
    func testAMutationThatMatchesNothingChangesNothing() {
        let before = layout([("a", .wide)])
        XCTAssertEqual(before.removing("nope"), before)
        XCTAssertEqual(before.resizing("nope", to: .tall), before)
        XCTAssertEqual(before.moving("nope", toTab: 0, at: 0), before)
        XCTAssertEqual(before.adding("a", toTab: 7), before)
    }
}
