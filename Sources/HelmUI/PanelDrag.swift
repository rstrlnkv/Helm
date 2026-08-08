import CoreGraphics

/// The three decisions a carried tile is made of, as arithmetic rather than as
/// a gesture.
///
/// The panel's drag is a third architecture and every rule in it was paid for
/// (ARCHITECTURE.md § Carrying a tile). They lived inside the `DragGesture`
/// closure, where the only way to try one was to press a tile and watch — so
/// they are here for the same reason `SidebarLayoutDrag` is here: a drag
/// landing in the wrong place is a failing test, not a thing somebody notices
/// after the layout has been written to disk.
///
/// The view keeps every piece of `@State`. What moved is the arithmetic.
public enum PanelDrag {
    /// How level two rectangles' centres have to be to count as one row.
    private static let sameRowTolerance: CGFloat = 4

    /// The measured frames less the tiles that are no longer drawn, or `nil`
    /// when they are all still there.
    ///
    /// **`onGeometryChange` does not fire on disappearance** — measured — so a
    /// removed tile leaves its last rectangle in the dictionary verbatim, and
    /// `hit` is a `first(where:)` over a dictionary whose iteration order Swift
    /// does not define. A stale rectangle is therefore not an occasional wrong
    /// answer: with two tabs whose top slots occupy the same rectangle, the
    /// tile under the pointer could resolve to the *other* tab's widget, and
    /// the panel writes a move to disk immediately, with no undo.
    ///
    /// Nothing to throw away is the common case — every pointer move of every
    /// drag — and it answers `nil` there so the caller has nothing to write.
    /// The frames are `@State` on the whole card, and the panel's other write
    /// to them is guarded the same way.
    public static func pruned(frames: [String: CGRect], live: Set<String>) -> [String: CGRect]? {
        guard frames.keys.contains(where: { !live.contains($0) }) else { return nil }
        return frames.filter { live.contains($0.key) }
    }

    /// The tile whose rectangle holds `point`, and that rectangle.
    ///
    /// The frame travels with the id because both callers need it — the pick-up
    /// insets it for the overlay, the target compares centres with it — and
    /// reading it back out of the dictionary was a second lookup into a
    /// container with no defined order.
    ///
    /// Ask over pruned frames. A removed tile made whatever took its place
    /// unpickable, because the hit resolved to an id that was no longer among
    /// the widgets and the gesture gave up.
    public static func hit(frames: [String: CGRect],
                           at point: CGPoint,
                           excluding: String? = nil) -> (id: String, frame: CGRect)? {
        frames.first { $0.key != excluding && $0.value.contains(point) }
            .map { ($0.key, $0.value) }
    }

    /// Whether the pointer has travelled past the target's centre, on the axis
    /// the move is happening along.
    ///
    /// **Containment alone oscillates against a tall neighbour**: entering its
    /// top edge swaps, and the swap puts the pointer in its *bottom* half,
    /// which reads as entered again — the utilities list bounced in place under
    /// a slowly moving pointer. Requiring the centre to be crossed is the
    /// hysteresis: after a swap the pointer is on the near side of the new
    /// centre, and nothing fires until it truly travels.
    ///
    /// `from` is the carried tile's own slot, `to` the slot under the pointer.
    /// Two tiles sharing a row have level centres, so that pair is compared on
    /// x — on y they could never be swapped at all.
    public static func crossed(from: CGRect, to: CGRect, pointer: CGPoint) -> Bool {
        let sameRow = abs(to.midY - from.midY) < sameRowTolerance
        return sameRow
            ? (to.midX > from.midX ? pointer.x > to.midX : pointer.x < to.midX)
            : (to.midY > from.midY ? pointer.y > to.midY : pointer.y < to.midY)
    }
}
