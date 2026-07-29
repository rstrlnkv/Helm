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

    /// Three tiers, in order: a module whose spin is still running takes the
    /// icon; otherwise the first module that tints it, which is the rule that
    /// was always here; otherwise the first module that has something to say.
    /// A spin lasts about a second and ends by itself, so the borrow is brief.
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
    public static func frame(spinUntil: Date?, now: Date, frameCount: Int) -> Int? {
        guard let spinUntil, spinUntil > now else { return nil }
        let phase = 1 - spinUntil.timeIntervalSince(now) / spinDuration
        return min(max(Int(phase * Double(frameCount)), 0), frameCount - 1)
    }

    /// Everything that changes the drawn icon, in one string, so the host can
    /// skip a redraw that would change nothing.
    ///
    /// The frame is part of it because a spin is thirty redraws a second of an
    /// otherwise identical icon: leave it out and every frame reports "nothing
    /// changed" and the ring stands still. Progress is bucketed because a
    /// countdown moves by far less than a pixel per tick.
    public static func redrawKey(style: String, size: String, tint: String?,
                                 progress: Double?, title: String?, frame: Int?) -> String {
        let part = { (value: String?) in value.map { "=" + $0 } ?? "-" }
        let bucket = progress.map { "=\(Int(($0 * 100).rounded()))" } ?? "-"
        return [style, size, part(tint), bucket, part(title),
                frame.map { "=\($0)" } ?? "-"].joined(separator: "|")
    }

    /// Whether the chosen appearance should actually move right now.
    public static func spins(_ appearance: StatusAppearance,
                             now: Date, reduceMotion: Bool) -> Bool {
        guard !reduceMotion else { return false }
        // A countdown owns this ring while it runs.
        guard appearance.timerProgress == nil else { return false }
        return (appearance.spinUntil ?? .distantPast) > now
    }
}
