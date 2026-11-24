import CoreGraphics

/// The three decisions a carried tile is made of, as arithmetic rather than as
/// a gesture.
///
/// The reasons behind each rule are on the doc comment of `gridDrag` in
/// `HelmPanel.swift`. Here they can be tried without pressing a tile; the view
/// keeps every piece of `@State`.
public enum PanelDrag {
    /// How level two rectangles' centres have to be to count as one row.
    private static let sameRowTolerance: CGFloat = 4

    /// The measured frames less the tiles that are no longer drawn, or `nil`
    /// when they are all still there.
    ///
    /// `onGeometryChange` does not fire on disappearance, so a removed tile
    /// leaves its last rectangle behind, and `hit` searches a dictionary with no
    /// defined order: with two tabs whose top slots share a rectangle, the tile
    /// under the pointer could resolve to the other tab's widget, and the panel
    /// writes a move to disk at once, with no undo.
    ///
    /// Nothing to throw away is the common case, every pointer move of every
    /// drag, and it answers `nil` there so the caller has nothing to write.
    public static func pruned(frames: [String: CGRect], live: Set<String>) -> [String: CGRect]? {
        guard frames.keys.contains(where: { !live.contains($0) }) else { return nil }
        return frames.filter { live.contains($0.key) }
    }

    /// The tile whose rectangle holds `point`, and that rectangle.
    ///
    /// The frame travels with the id because both callers need it: the pick-up
    /// insets it for the overlay, the target compares centres with it. Ask over
    /// pruned frames, or a removed tile's id makes whatever took its place
    /// unpickable.
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
    /// top edge swaps, and the swap puts the pointer in its bottom half, which
    /// reads as entered again. Requiring the centre to be crossed is the
    /// hysteresis: after a swap the pointer is on the near side of the new
    /// centre, and nothing fires until it truly travels.
    ///
    /// `from` is the carried tile's own slot, `to` the slot under the pointer.
    /// Two tiles sharing a row have level centres, so that pair is compared on
    /// x — on y they could never be swapped at all.
    public static func crossed(from: CGRect, to: CGRect, pointer: CGPoint) -> Bool {
        let sameRow = abs(to.midY - from.midY) < sameRowTolerance
        return sameRow
            ? travelled(from: from.midX, past: to.midX, pointer: pointer.x)
            : travelled(from: from.midY, past: to.midY, pointer: pointer.y)
    }

    /// One axis of the above: the pointer is past `target` when it is on the far
    /// side of it *from where the tile started*.
    ///
    /// **Two centres level on the axis being compared have no far side.**
    /// `HelmPanel.gridDrag` falls back to `frames[carried.id] ?? over.frame`
    /// when pruning has just dropped the carried tile (a module switched off
    /// mid-drag), and full-width tiles all share `midX`, so a rectangle can be
    /// compared with itself or with one it is exactly under. Answering there
    /// would fire a swap from a pointer that has not moved, written to disk with
    /// no undo.
    ///
    /// Non-finite coordinates fall out of the same three comparisons: every one
    /// of them is false against a `nan`, so a bounced scroll picks nothing up.
    private static func travelled(from origin: CGFloat,
                                  past target: CGFloat,
                                  pointer: CGFloat) -> Bool {
        if target > origin { return pointer > target }
        if target < origin { return pointer < target }
        return false
    }
}
