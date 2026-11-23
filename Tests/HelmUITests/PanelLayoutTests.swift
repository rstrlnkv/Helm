import XCTest
@testable import HelmUI

private func layout(_ widgets: [(String, PanelWidgetSize)]) -> PanelLayout {
    PanelLayout(tabs: [.init(id: "t", seed: "main", name: nil,
                             widgets: widgets.map { .init(widget: $0.0, size: $0.1) })])
}

/// What the panel remembers, and what it must never forget by accident.
final class PanelLayoutTests: XCTestCase {

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

    /// A layout written before this build decodes whole rather than taking the
    /// document down with it: `JSONDecoder` gives up on the document, not the
    /// field, so a missing `dismissed` or `hidden` list, or a tab without a
    /// glyph, would each have thrown under the synthesised decoder. The
    /// *known* size is the control for the lenient one above: it still decodes
    /// as itself, so the lenient path is not quietly answering `wide` to everything.
    func testALayoutFromAnOlderBuildDecodesWhole() throws {
        let json = """
        {"tabs":[{"id":"t","widgets":[{"widget":"vpn","size":"tall"}]}]}
        """
        let decoded = try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.allSlots.map(\.widget), ["vpn"])
        XCTAssertEqual(decoded.allSlots.first?.size, .tall)
        XCTAssertNil(decoded.tabs.first?.glyph)
        XCTAssertTrue(decoded.dismissed.isEmpty)
        XCTAssertTrue(decoded.hidden.isEmpty)
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

    func testTheNoteSurvivesTheRoundTrip() throws {
        let before = layout([("vpn", .wide), ("disk", .wide)]).removing("disk")
        let data = try JSONEncoder().encode(before)
        XCTAssertEqual(try JSONDecoder().decode(PanelLayout.self, from: data).dismissed, ["disk"])
    }

    /// Neither the dismissed list nor the hidden one re-adds a tile on the next read.
    func testNeitherRefusalIsUndoneByAReread() {
        var l = layout([("layout", .wide), ("vpn", .wide)]).removing("layout").hiding("homebrew")
        for _ in 0..<5 { l = l.reconciled(arriving: ["layout", "vpn", "homebrew"]) }
        XCTAssertEqual(l.allSlots.map(\.widget), ["vpn"])
        XCTAssertTrue(l.isHidden("homebrew"))
    }
}
