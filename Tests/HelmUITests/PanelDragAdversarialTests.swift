import XCTest
@testable import HelmUI

/// The three rules of a carried tile, met by the states a real gesture can be
/// in the middle of.
///
/// `PanelDragTests` argues with each rule once, on its own, in the shape the
/// rule was written for. This file is the other half: the *combinations*, and
/// the inputs a pointer and a geometry callback can really produce — a tile
/// removed while it is in the hand, a pointer exactly on the seam between two
/// slots, a rectangle with no area, a coordinate from a scroll bounce.
///
/// Every assertion here is structural. The wrong answers in this file are
/// coin tosses (a `first(where:)` over a dictionary Swift does not order) or
/// half-plane tests that happen to be right for half the screen, so an
/// assertion that a single lookup answered "disk" can come up green with the
/// rule deleted. Where a lookup could pass by luck the invariant is stated
/// over the whole input instead.
final class PanelDragAdversarialTests: XCTestCase {

    /// The panel's real geometry: a two-column grid of 148 pt slots, 8 pt apart.
    private func slot(column: Int, row: Int) -> CGRect {
        CGRect(x: CGFloat(column) * 156, y: CGFloat(row) * 156, width: 148, height: 148)
    }

    // MARK: - Pruning and the hit that follows it

    /// Pruning and the hit are one decision made in two calls, and the panel
    /// makes the second one over `frames` — the `@State` it has just written —
    /// not over the value `pruned` answered. So the pair has to agree: what
    /// pruning throws away must be exactly what the hit can no longer resolve
    /// to, for *every* point in the departed tile's rectangle rather than for
    /// the one point a test picked.
    ///
    /// Asserted over a sweep of the whole rectangle. With two tiles occupying
    /// the identical slot — the shape a tab switch leaves behind — a single
    /// probe answers the right id half the time with the pruning deleted.
    func testEveryPointInAStaleRectangleResolvesToTheTileNowDrawnThere() {
        let taken = slot(column: 0, row: 0)
        let frames = ["gone": taken, "disk": taken, "brew": slot(column: 1, row: 0)]
        let kept = PanelDrag.pruned(frames: frames, live: ["disk", "brew"]) ?? [:]

        var answers: Set<String> = []
        for x in stride(from: taken.minX, to: taken.maxX, by: 7) {
            for y in stride(from: taken.minY, to: taken.maxY, by: 7) {
                answers.insert(PanelDrag.hit(frames: kept, at: CGPoint(x: x, y: y))?.id ?? "—")
            }
        }
        XCTAssertEqual(answers, ["disk"],
                       "a point inside the departed tile's rectangle answered \(answers.sorted()) "
                       + "— the stale rectangle is still resolvable")
    }

    /// A tab with nothing on it: every frame is stale at once. The answer is a
    /// dictionary (there *was* something to throw away), it is empty, and no
    /// point in the panel picks anything up.
    ///
    /// The empty-dictionary and the nil answer are different instructions to
    /// the caller — `if let kept = … { frames = kept }` — so "nothing is live"
    /// must not arrive as "nothing changed", which would leave every stale
    /// rectangle in place.
    func testATabWithNoTilesLeftPrunesToNothingRatherThanToNoChange() {
        let frames = ["disk": slot(column: 0, row: 0), "brew": slot(column: 1, row: 0)]

        let pruned = PanelDrag.pruned(frames: frames, live: [])

        XCTAssertEqual(pruned?.isEmpty, true,
                       "an empty tab answered \(String(describing: pruned)) — nil there means "
                       + "the caller keeps every rectangle of a tab that is gone")
        XCTAssertNil(PanelDrag.hit(frames: pruned ?? frames, at: CGPoint(x: 74, y: 74)))
    }

    /// Ids that are live but have no rectangle yet — a tile drawn this frame
    /// whose `onGeometryChange` has not fired — are not a reason to write.
    /// `live` is a superset of the keys, so nothing is stale and the answer is
    /// nothing.
    func testATileDrawnBeforeItsGeometryArrivedIsNotAPruning() {
        let frames = ["disk": slot(column: 0, row: 0)]
        XCTAssertNil(PanelDrag.pruned(frames: frames, live: ["disk", "brew", "vpn"]))
    }

    /// Pruning is idempotent: running it over its own answer finds nothing left
    /// to do. A pruning that always answered a dictionary would put a `@State`
    /// write back on every pointer move of every drag, which is the reason it
    /// answers `nil` at all.
    func testPruningItsOwnAnswerFindsNothingToDo() {
        let frames = ["gone": slot(column: 0, row: 0), "disk": slot(column: 1, row: 0)]
        let once = PanelDrag.pruned(frames: frames, live: ["disk"])

        XCTAssertNotNil(once, "nothing was pruned, so the second pass proves nothing")
        XCTAssertNil(PanelDrag.pruned(frames: once ?? [:], live: ["disk"]))
    }

    // MARK: - The seam between two slots

    /// The panel's slots are 8 pt apart, but a full-width tile stacked on
    /// another shares an edge exactly. A pointer on that edge must belong to
    /// exactly one of them — not to both (which makes the answer the
    /// dictionary's iteration order, and the panel writes the move to disk with
    /// no undo) and not to neither.
    ///
    /// Asserted as "how many rectangles hold this point", which is the property,
    /// rather than as "which id came back", which a coin toss satisfies half the
    /// time.
    func testAPointerOnASharedEdgeBelongsToExactlyOneTile() {
        let upper = CGRect(x: 0, y: 0, width: 304, height: 148)
        let lower = CGRect(x: 0, y: 148, width: 304, height: 148)
        let frames = ["upper": upper, "lower": lower]

        for x in stride(from: CGFloat(0), to: 304, by: 19) {
            let seam = CGPoint(x: x, y: 148)
            let holders = frames.filter { $0.value.contains(seam) }.keys.sorted()
            XCTAssertEqual(holders.count, 1,
                           "the seam at x=\(x) is inside \(holders) — the tile under the "
                           + "pointer is whichever the dictionary happens to yield first")
            XCTAssertEqual(PanelDrag.hit(frames: frames, at: seam)?.id, holders.first)
        }
    }

    // MARK: - A rectangle with no area

    /// A tile mid-collapse — a reveal closing, a widget being removed — reports
    /// a rectangle with no height for a frame or two, and `onGeometryChange`
    /// delivers it. It cannot be picked up (there is nothing under the pointer
    /// to pick up), and it must not swallow the tile beside it.
    ///
    /// The neighbour is asserted *first*: a test that only checks the collapsed
    /// tile answers nothing would pass on a lookup that answers nothing anywhere.
    func testATileWithNoAreaIsNeitherPickedUpNorSwallowsItsNeighbour() {
        let collapsed = CGRect(x: 0, y: 0, width: 148, height: 0)
        let frames = ["collapsing": collapsed, "brew": slot(column: 1, row: 0)]

        XCTAssertEqual(PanelDrag.hit(frames: frames, at: CGPoint(x: 200, y: 74))?.id, "brew",
                       "nothing is resolvable at all, so the assertion below proves nothing")
        XCTAssertNil(PanelDrag.hit(frames: frames, at: CGPoint(x: 74, y: 0)))
        XCTAssertNil(PanelDrag.hit(frames: frames, at: .zero))
    }

    // MARK: - Coordinates a scroll bounce produces

    /// A trackpad bounce and an interrupted animation both hand SwiftUI a
    /// location outside the container, and a geometry read taken mid-transition
    /// can arrive non-finite. Neither may pick a tile up, and neither may
    /// report a crossing — the panel writes the layout to disk on a crossing.
    ///
    /// A real point is asserted first on the same frames, so "nothing happened"
    /// is not what makes this green.
    func testANonFiniteOrNegativePointerNeitherPicksUpNorSwaps() {
        let carried = slot(column: 0, row: 0)
        let target = slot(column: 1, row: 0)
        let frames = ["disk": carried, "brew": target]

        XCTAssertEqual(PanelDrag.hit(frames: frames, at: CGPoint(x: 200, y: 74))?.id, "brew",
                       "the frames resolve nothing, so the refusals below are vacuous")
        XCTAssertTrue(PanelDrag.crossed(from: carried, to: target,
                                        pointer: CGPoint(x: 240, y: 74)),
                      "a crossing cannot happen at all, so the refusals below are vacuous")

        for point in [CGPoint(x: CGFloat.nan, y: CGFloat.nan),
                      CGPoint(x: CGFloat.infinity, y: 74),
                      CGPoint(x: -CGFloat.infinity, y: -CGFloat.infinity),
                      CGPoint(x: -400, y: -400)] {
            XCTAssertNil(PanelDrag.hit(frames: frames, at: point),
                         "\(point) picked a tile up")
        }
        XCTAssertFalse(PanelDrag.crossed(from: carried, to: target,
                                         pointer: CGPoint(x: CGFloat.nan, y: CGFloat.nan)),
                       "a coordinate that is not a number reported a crossing, and a "
                       + "crossing is written to disk")
    }

    // MARK: - The carried tile's own slot going away mid-gesture

    /// **The three rules meeting.** Switch a module off in Settings while its
    /// tile is in the hand: `reload` drops the widget, `PanelDrag.pruned` throws
    /// its rectangle away on the next pointer move — and `dragging` is still
    /// set, because only `onEnded` clears it. `HelmPanel.gridDrag` then reaches
    ///
    ///     let slot = frames[carried.id] ?? over.frame
    ///
    /// with `frames[carried.id]` gone, and asks whether the pointer has crossed
    /// from a rectangle to *itself*.
    ///
    /// Two identical rectangles have identical centres, so there is no axis the
    /// move is happening along and nothing can have been travelled past. The
    /// answer must be "no crossing" for every pointer position — otherwise the
    /// hysteresis the rule exists to provide is gone exactly when the panel is
    /// least sure what it is holding, and a layout write with no undo is decided
    /// by which half of the target the pointer happens to be in.
    ///
    /// It answered `true` for the whole left half: `sameRow` is true (the centres
    /// are 0 apart), `to.midX > from.midX` is false for equal rectangles, so the
    /// arm taken was `pointer.x < to.midX`.
    func testARectangleIsNeverCrossedWithItself() {
        let tile = slot(column: 1, row: 2)
        for x in stride(from: tile.minX, through: tile.maxX, by: 7) {
            for y in stride(from: tile.minY, through: tile.maxY, by: 7) {
                XCTAssertFalse(PanelDrag.crossed(from: tile, to: tile,
                                                 pointer: CGPoint(x: x, y: y)),
                               "the pointer at (\(x), \(y)) is reported as having crossed "
                               + "from a rectangle into itself")
            }
        }
    }

    /// The same degeneracy without the equal rectangles, and the reason it is
    /// worth a rule rather than a special case at the call site.
    ///
    /// Two full-width tiles share `midX` exactly — every full-width tile does.
    /// Mid-animation their `midY` can pass within the 4 pt `sameRowTolerance`
    /// of each other (a tile growing out of a reveal is 0 pt high and then 3 pt
    /// high, and `onGeometryChange` delivers every step), and the pair is then
    /// compared **sideways**: two rectangles with the same `midX`, which is the
    /// equal-rectangle case again.
    ///
    /// The same half-plane answer. Nothing has been travelled past on the x axis
    /// when the two centres are level on it, so a swap fired from a pointer
    /// standing still in the left half of the panel.
    func testTwoTilesWithLevelCentresOnTheComparedAxisHaveNothingToCross() {
        // Two full-width tiles, one of them 3 pt into a reveal: same midX, and
        // their midY are inside the 4 pt tolerance, so the pair is compared on x.
        let carried = CGRect(x: 0, y: 0, width: 304, height: 148)
        let growing = CGRect(x: 0, y: 71, width: 304, height: 6)
        XCTAssertLessThan(abs(growing.midY - carried.midY), 4,
                          "these two are not inside the tolerance, so this tests the y axis "
                          + "and not the case it was written for")

        for x in stride(from: CGFloat(0), through: 304, by: 19) {
            XCTAssertFalse(PanelDrag.crossed(from: carried, to: growing,
                                             pointer: CGPoint(x: x, y: 74)),
                           "a crossing was reported at x=\(x) between two rectangles whose "
                           + "centres are level on the axis being compared")
        }
    }

    /// What must keep working once the above is fixed: a genuine sideways swap
    /// between two tiles that really do sit side by side. Pinned here so a fix
    /// for the degenerate case cannot become "answer false whenever `sameRow`".
    func testASidewaysCrossingBetweenTwoRealNeighboursStillFires() {
        let left = slot(column: 0, row: 0)
        let right = slot(column: 1, row: 0)

        XCTAssertFalse(PanelDrag.crossed(from: left, to: right,
                                         pointer: CGPoint(x: 160, y: 74)),
                       "two points inside the neighbour is not yet a crossing")
        XCTAssertTrue(PanelDrag.crossed(from: left, to: right,
                                        pointer: CGPoint(x: 231, y: 74)),
                      "past the neighbour's centre is a crossing")
        XCTAssertTrue(PanelDrag.crossed(from: right, to: left,
                                        pointer: CGPoint(x: 73, y: 74)),
                      "and the same journey the other way")
    }

    /// The exclusion meets the only candidate there is: one tile left on the
    /// tab, carried. There is nothing to swap with, and the answer must be
    /// nothing rather than the tile itself — swapping a tile with its own slot
    /// is a write to disk that changes nothing and animates anyway.
    ///
    /// Asserted across the whole rectangle: with one entry the dictionary has
    /// no order to get wrong, so a single probe cannot tell an exclusion that
    /// works from one that is never reached.
    func testTheLastTileOnATabIsNeverItsOwnSwapTarget() {
        let only = slot(column: 0, row: 0)
        let frames = ["disk": only]

        for x in stride(from: only.minX, to: only.maxX, by: 11) {
            for y in stride(from: only.minY, to: only.maxY, by: 11) {
                let point = CGPoint(x: x, y: y)
                XCTAssertEqual(PanelDrag.hit(frames: frames, at: point)?.id, "disk",
                               "the tile is not resolvable at (\(x), \(y)) without the "
                               + "exclusion, so excluding it proves nothing")
                XCTAssertNil(PanelDrag.hit(frames: frames, at: point, excluding: "disk"),
                             "the carried tile answered its own hit at (\(x), \(y))")
            }
        }
    }

    /// An exclusion naming a tile that is no longer there — the id the drag
    /// started with, after pruning took its frame — excludes nothing, and the
    /// tile actually under the pointer is still found. The alternative is a
    /// drag that goes dead the moment its own tile disappears.
    func testAnExclusionForATileThatHasGoneStillFindsWhatIsUnderThePointer() {
        let frames = ["brew": slot(column: 1, row: 0)]
        let hit = PanelDrag.hit(frames: frames, at: CGPoint(x: 200, y: 74), excluding: "disk")

        XCTAssertEqual(hit?.id, "brew")
        XCTAssertEqual(hit?.frame, frames["brew"])
    }
}
