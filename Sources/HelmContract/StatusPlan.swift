import Foundation

/// Which module's appearance the menu bar draws, and whether it moves.
///
/// Pulled out of `StatusItemController` so it can be asked questions without a
/// status bar, a run loop or a real module. It lives beside `StatusAppearance`
/// rather than in `HelmRuntime` because `HelmRuntime` does not depend on
/// `HelmContract`, and one decision function is not worth that edge.
public enum StatusPlan {
    /// How long a spin lasts. The module that asks for one uses this to compute
    /// `spinUntil`; the host needs it to know which frame belongs to now. One
    /// number, so the two cannot drift.
    public static let spinDuration: TimeInterval = 1.2

    /// Four tiers, in order: a module counting down owns the icon while it
    /// counts; otherwise a module whose spin is still running takes it;
    /// otherwise the first module that tints it, which is the rule that was
    /// always here; otherwise the first module that has something to say. A
    /// spin lasts about a second and ends by itself, so the borrow is brief.
    ///
    /// **The countdown tier is first, and `spins` depends on it being first.**
    /// A countdown is continuous state and a spin is a moment; the moment must
    /// not interrupt the state, or the arc jumps backwards and reads as a bug.
    /// `spins` enforces that by refusing to move an appearance that carries a
    /// `timerProgress` — but it can only see the appearance this function
    /// returns, and no descriptor produces one holding both fields: Keep Awake
    /// counts down on its appearance, VPN asks for the spin on another. So
    /// while the spin tier ranked first, `spins` was handed VPN's appearance,
    /// found no countdown on it, and the rule never fired once. Ranking the
    /// countdown above the spin is what makes that guard reachable, and on
    /// screen it is the difference between a red ring reading 14:22 and the
    /// same ring replaced by a grey spinner for 1.2 seconds.
    ///
    /// The cost is stated rather than hidden: there is one status item and one
    /// title slot, and while a countdown holds them a VPN firing shows neither
    /// the spin nor the name. The banner mode exists for people who want to be
    /// told regardless.
    ///
    /// When two spins overlap the **newest** wins, which is why that tier is a
    /// `max` and not a `first`. Taking the first would settle the question by
    /// `ModuleOrder` — a module's own feedback would sit invisible behind an
    /// unrelated module that happened to sort earlier, which is the failure a
    /// spin borrowing the icon at all exists to prevent, one level up. The
    /// newest spin also ends last, so deferring to it truncates nothing.
    ///
    /// The title tier is last, and below the tint deliberately. A module may
    /// carry a title with no tint and no live spin — VPN names the connection a
    /// rule raised for three seconds, while the ring turns for 1.2 s — and
    /// without this tier that name was dropped the instant the spin ended.
    /// Keeping it *below* the tint is the same rule the countdown's suppression
    /// of the spin encodes: Keep Awake tints while a countdown runs, and a name
    /// is a moment, which must not interrupt continuous state. A name arriving
    /// while another module owns the icon is simply not shown — the spin that
    /// went with it still happened, and that is the half that carries the news.
    public static func choose(_ appearances: [StatusAppearance], now: Date) -> StatusAppearance {
        if let counting = appearances.first(where: { $0.timerProgress != nil }) { return counting }
        let spinEnd = { (a: StatusAppearance) in a.spinUntil ?? .distantPast }
        if let newest = appearances.filter({ spinEnd($0) > now }).max(by: { spinEnd($0) < spinEnd($1) }) {
            return newest
        }
        return appearances.first { $0.tintToken != nil }
            ?? appearances.first { $0.title != nil }
            ?? .inactive
    }

    /// Which still of a spin belongs to `now`, or nil when nothing is spinning.
    ///
    /// The host draws the frames but must not learn how long a spin lasts from
    /// the module that asked for one — the duration lives here, beside the
    /// `spinUntil` it produced. The result is always a real index of an array
    /// of `frameCount`: a clock that jumps, or a module asking for a longer
    /// window than one spin, otherwise subscripts past the end.
    ///
    /// **The bounds are applied to the `Double`, before the conversion.** They
    /// used to be applied after — `min(max(Int(phase * Double(frameCount)), 0),
    /// frameCount - 1)` — where they protected nothing, because `Int(_:)` traps
    /// on a value outside `Int`'s range and on one that is not a number, and it
    /// ran first. `spinUntil` arrives from a module over JSON as a `Date`, which
    /// is a `Double` of seconds; nothing between that payload and this line
    /// bounds it, so the same family of crashes that `Clamped` was written for
    /// reached the menu bar. The helper cannot be used here — `HelmRuntime`
    /// depends on this target — so the order is spelled out instead.
    ///
    /// The empty array is refused first for the same arithmetic: `phase` is
    /// infinite for a wild `spinUntil`, `infinity * 0` is NaN, and a NaN passes
    /// through `min` and `max` untouched to trap at the conversion anyway.
    public static func frame(spinUntil: Date?, now: Date, frameCount: Int) -> Int? {
        guard let spinUntil, spinUntil > now, frameCount > 0 else { return nil }
        let phase = 1 - spinUntil.timeIntervalSince(now) / spinDuration
        return Int(min(max(phase * Double(frameCount), 0), Double(frameCount - 1)))
    }

    /// Everything that changes the drawn icon, in one string, so the host can
    /// skip a redraw that would change nothing.
    ///
    /// The frame is part of it because a spin is thirty redraws a second of an
    /// otherwise identical icon: leave it out and every frame reports "nothing
    /// changed" and the ring stands still. Progress is bucketed because a
    /// countdown moves by far less than a pixel per tick. The spin's own
    /// colour is part of it too: it is drawn instead of the tint while a spin
    /// runs, so two colours at the same frame index must not compare equal.
    ///
    /// **The bucket is bounded before it is converted**, the way `frame` above
    /// is and for the same reason: `Int(_:)` of a `Double` traps outside
    /// `Int`'s range and on a value that is not a number, and this line runs
    /// first — a status tick reaches it about once a second, before
    /// `MenuBarIcon.make` sees the same number. `timerProgress` is a field of a
    /// public struct any module's descriptor fills in, and nothing between
    /// that and here says how large it may be.
    ///
    /// The bounds are the ones the icon draws with, so the key still says what
    /// the icon shows: `MenuBarIcon.make` clamps to 0…1, and it strokes no arc
    /// for a value that is not a number — the same nothing it draws at 0.
    /// `HelmRuntime`'s `clamped(to:whenNotANumber:)` is that sentence in one
    /// call and cannot be used here, because `HelmRuntime` depends on this
    /// target; as with `frame`, the order is spelled out instead.
    public static func redrawKey(style: String, size: String, tint: String?,
                                 progress: Double?, title: String?, frame: Int?,
                                 spinTint: String? = nil) -> String {
        let part = { (value: String?) in value.map { "=" + $0 } ?? "-" }
        let bucket = progress.map { p in
            let drawn = p.isNaN ? 0 : min(max(p, 0), 1)
            return "=\(Int((drawn * 100).rounded()))"
        } ?? "-"
        return [style, size, part(tint), bucket, part(title),
                frame.map { "=\($0)" } ?? "-", part(spinTint)].joined(separator: "|")
    }

    /// Whether the chosen appearance should actually move right now.
    public static func spins(_ appearance: StatusAppearance,
                             now: Date, reduceMotion: Bool) -> Bool {
        guard !reduceMotion else { return false }
        // A countdown owns this ring while it runs. Reachable only because
        // `choose` ranks a countdown above a spin: this is the second half of
        // that rule, and for one release it was the whole of it and inert.
        guard appearance.timerProgress == nil else { return false }
        return (appearance.spinUntil ?? .distantPast) > now
    }
}
