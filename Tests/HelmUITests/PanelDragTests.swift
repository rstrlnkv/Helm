import XCTest
@testable import HelmUI

/// The three decisions a carried tile is made of, argued with rather than
/// dragged.
///
/// Each one shipped as a defect first, and each one lived inside a
/// `DragGesture` closure where the only way to try it was to press a tile and
/// watch. They are here for the same reason `SidebarLayoutDrag` is here: a
/// drag that lands in the wrong place should be a failing test, not something
/// somebody notices after the layout has been written to disk.
final class PanelDragTests: XCTestCase {

    // MARK: - Frames of tiles that are no longer drawn

    /// **`onGeometryChange` does not fire on disappearance.** A removed tile
    /// leaves its last rectangle in the dictionary verbatim, and the hit
    /// lookups are `first(where:)` over a dictionary whose iteration order
    /// Swift does not define — so with two tabs whose top slots occupy the same
    /// rectangle, the tile under the pointer could resolve to the *other*
    /// tab's widget, and the move was written to disk immediately with no undo.
    ///
    /// Asserted on the key set rather than on which id a lookup happens to
    /// answer: the wrong answer was a coin toss, and a test of the coin can
    /// come up right with the pruning deleted.
    func testPruningKeepsExactlyTheTilesStillDrawn() {
        let frames: [String: CGRect] = [
            "disk": CGRect(x: 0, y: 0, width: 148, height: 148),
            "vpn": CGRect(x: 0, y: 0, width: 148, height: 148),   // the other tab's top slot
            "brew": CGRect(x: 156, y: 0, width: 148, height: 148),
        ]
        guard let pruned = PanelDrag.pruned(frames: frames, live: ["disk", "brew"]) else {
            return XCTFail("a stale rectangle has to be thrown away")
        }
        XCTAssertEqual(Set(pruned.keys), ["disk", "brew"])
        XCTAssertEqual(pruned["disk"], frames["disk"])
        XCTAssertEqual(pruned["brew"], frames["brew"])
    }

    /// Nothing to throw away is the common case — every pointer move of every
    /// drag — and the answer is nothing, so the view has nothing to write.
    ///
    /// `frames` is `@State` on the whole card, and the panel guards its other
    /// write to it the same way (`if frames[widget.id] != rect`). A pruning that
    /// always answered a dictionary would put a write back on every move.
    func testNothingIsThrownAwayWhenEveryTileIsStillDrawn() {
        let frames: [String: CGRect] = ["disk": CGRect(x: 0, y: 0, width: 148, height: 148)]
        XCTAssertNil(PanelDrag.pruned(frames: frames, live: ["disk"]))
    }

    // MARK: - Which tile is under the pointer

    /// **A removed tile made whatever took its place unpickable**, because the
    /// hit resolved to an id that was no longer among the widgets and the
    /// gesture returned. Pruned first, the rectangle the departed tile left
    /// behind belongs to the tile now drawn there.
    func testTheTileThatTookARemovedTilesPlaceIsPickable() {
        let slot = CGRect(x: 0, y: 0, width: 148, height: 148)
        let kept = PanelDrag.pruned(frames: ["gone": slot, "disk": slot], live: ["disk"]) ?? [:]
        XCTAssertEqual(PanelDrag.hit(frames: kept, at: CGPoint(x: 74, y: 74))?.id, "disk")
    }

    /// The frame travels with the id. The overlay needs the rectangle, and
    /// reading it back out of the dictionary was a second lookup that could
    /// answer a different tile than the one just resolved.
    func testAHitCarriesTheFrameItResolvedTo() {
        let slot = CGRect(x: 156, y: 0, width: 148, height: 148)
        let hit = PanelDrag.hit(frames: ["brew": slot], at: CGPoint(x: 200, y: 40))
        XCTAssertEqual(hit?.frame, slot)
    }

    /// A press in the gap between two tiles picks up nothing. The point two
    /// points to its right is asserted as well, or the gap reads as empty for a
    /// lookup that answers nothing anywhere.
    func testAPointInsideNoTileIsNoHit() {
        let frames: [String: CGRect] = [
            "disk": CGRect(x: 0, y: 0, width: 148, height: 148),
            "brew": CGRect(x: 156, y: 0, width: 148, height: 148),
        ]
        XCTAssertNil(PanelDrag.hit(frames: frames, at: CGPoint(x: 152, y: 74)))
        XCTAssertEqual(PanelDrag.hit(frames: frames, at: CGPoint(x: 158, y: 74))?.id, "brew")
    }

    /// The carried tile is never its own target: the second lookup asks which
    /// *other* slot the pointer is over. Without the exclusion the same point
    /// answers it, so the refusal is the exclusion and not an empty lookup.
    func testTheCarriedTileIsExcludedFromItsOwnHit() {
        let frames = ["disk": CGRect(x: 0, y: 0, width: 148, height: 148)]
        let middle = CGPoint(x: 74, y: 74)
        XCTAssertEqual(PanelDrag.hit(frames: frames, at: middle)?.id, "disk")
        XCTAssertNil(PanelDrag.hit(frames: frames, at: middle, excluding: "disk"))
    }

    // MARK: - Hysteresis

    /// **Containment alone oscillates against a tall neighbour.** Entering its
    /// top edge swapped, and the swap put the pointer in its *bottom* half,
    /// which read as entered again — the utilities list bounced in place under
    /// a slowly moving pointer. The centre has to be crossed on the axis the
    /// move is happening along.
    func testEnteringATallNeighboursEdgeIsNotYetACrossing() {
        let carried = CGRect(x: 0, y: 0, width: 148, height: 148)
        let tall = CGRect(x: 0, y: 156, width: 304, height: 300)
        // Inside the neighbour by two points, and 148 pt short of its centre.
        XCTAssertFalse(PanelDrag.crossed(from: carried, to: tall,
                                         pointer: CGPoint(x: 74, y: 158)))
        XCTAssertTrue(PanelDrag.crossed(from: carried, to: tall,
                                        pointer: CGPoint(x: 74, y: 310)))
    }

    /// Travelling the other way the comparison turns over: a tile moving up
    /// crosses when the pointer is *above* the target's centre.
    func testCrossingUpwardsComparesTheOtherWay() {
        let carried = CGRect(x: 0, y: 156, width: 148, height: 148)
        let above = CGRect(x: 0, y: 0, width: 148, height: 148)
        XCTAssertFalse(PanelDrag.crossed(from: carried, to: above,
                                         pointer: CGPoint(x: 74, y: 100)))
        XCTAssertTrue(PanelDrag.crossed(from: carried, to: above,
                                        pointer: CGPoint(x: 74, y: 60)))
    }

    /// Two tiles sharing a row are compared on x: their centres are level, so
    /// the vertical test would never fire and the pair could not be swapped.
    func testTilesInOneRowAreCrossedSideways() {
        let left = CGRect(x: 0, y: 0, width: 148, height: 148)
        let right = CGRect(x: 156, y: 0, width: 148, height: 148)
        XCTAssertFalse(PanelDrag.crossed(from: left, to: right,
                                         pointer: CGPoint(x: 200, y: 74)))
        XCTAssertTrue(PanelDrag.crossed(from: left, to: right,
                                        pointer: CGPoint(x: 240, y: 74)))
    }
}
