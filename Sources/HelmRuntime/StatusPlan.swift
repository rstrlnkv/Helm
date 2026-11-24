import Foundation
import HelmContract

/// Which module's appearance the menu bar draws, and whether it moves.
///
/// Pulled out of `StatusItemController` so it can be asked questions without a
/// status bar, a run loop or a real module.
///
/// It is four decisions the *host* makes about the menu bar out of what modules
/// reported, which is the plumbing `HelmRuntime` is for; `HelmRuntime` depends
/// on `HelmContract` and not the other way (Architecture/Targets.md § Targets).
public enum StatusPlan {
    /// How long a spin lasts. The module that asks for one uses this to compute
    /// `spinUntil`; the host needs it to know which frame belongs to now. One
    /// number, so the two cannot drift.
    public static let spinDuration: TimeInterval = 1.2

    /// Four tiers, in order: a module counting down owns the icon while it
    /// counts; otherwise a module whose spin is still running takes it;
    /// otherwise the first module that tints it; otherwise the first module
    /// that has something to say. A spin lasts about a second and ends by
    /// itself, so the borrow is brief.
    ///
    /// **The countdown tier is first, and `spins` depends on it.** A countdown
    /// is continuous state and a spin is a moment; the moment must not
    /// interrupt the state, or the arc jumps backwards. `spins` refuses to move
    /// an appearance with a `timerProgress`, but it only sees the appearance
    /// returned here, and no descriptor holds both fields (Keep Awake counts
    /// down, VPN spins), so the guard is reachable only with the countdown
    /// ranked above the spin.
    ///
    /// The cost: one status item and one title slot, so while a countdown holds
    /// them a VPN firing shows neither the spin nor the name. The banner mode
    /// is for people who want to be told regardless.
    ///
    /// When two spins overlap the **newest** wins (`max`, not `first`), so a
    /// module's own feedback never hides behind an unrelated module that sorts
    /// earlier. The newest spin also ends last, so deferring to it truncates
    /// nothing.
    ///
    /// The title tier is last, below the tint on purpose. A module may carry a
    /// title with no tint and no live spin (VPN names a connection for longer
    /// than the ring turns), and this tier keeps the name up after the spin. A
    /// name is a moment and must not interrupt a tint's continuous state; a name
    /// arriving while another module owns the icon is not shown, and the spin
    /// that went with it carries the news.
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
    /// **The bounds are applied to the `Double`, before the conversion**:
    /// `Int(_:)` traps on a value outside `Int`'s range and on one that is not a
    /// number, and `spinUntil` arrives from a module unbounded.
    ///
    /// The empty array is refused first: `phase` is infinite for a wild
    /// `spinUntil`, `infinity * 0` is NaN, and a NaN passes through
    /// `clamped(to:)` to trap at the conversion. Past that guard the product is
    /// infinite at worst and the plain clamp is the whole answer.
    public static func frame(spinUntil: Date?, now: Date, frameCount: Int) -> Int? {
        guard let spinUntil, spinUntil > now, frameCount > 0 else { return nil }
        let phase = 1 - spinUntil.timeIntervalSince(now) / spinDuration
        return Int((phase * Double(frameCount)).clamped(to: 0...Double(frameCount - 1)))
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
    /// **The bucket is bounded before it is converted**, as in `frame`:
    /// `timerProgress` is a field any module fills in, unbounded, and this runs
    /// before `MenuBarIcon.make` sees the same number.
    ///
    /// The bounds are the ones the icon draws with, so the key still says what
    /// the icon shows: `MenuBarIcon.make` clamps to 0…1 and draws a NaN as 0.
    public static func redrawKey(style: String, size: String, tint: String?,
                                 progress: Double?, title: String?, frame: Int?,
                                 spinTint: String? = nil) -> String {
        let part = { (value: String?) in value.map { "=" + $0 } ?? "-" }
        let bucket = progress.map { p in
            "=\(Int((p.clamped(to: 0...1, whenNotANumber: 0) * 100).rounded()))"
        } ?? "-"
        return [style, size, part(tint), bucket, part(title),
                frame.map { "=\($0)" } ?? "-", part(spinTint)].joined(separator: "|")
    }

    /// The title as the menu bar can actually carry it, or nil when there is
    /// nothing left to draw.
    ///
    /// **The one part of the status item a stranger writes.** A VPN
    /// configuration's name is free text from `scutil --nc list`, and a long one
    /// would take over the whole menu bar.
    ///
    /// 24 characters: still a label rather than a takeover, even in the widest
    /// glyphs, on the narrowest display shared with every other menu extra. The
    /// ellipsis is inside the bound, so a name that was cut looks cut.
    ///
    /// Here because the bound is a fact about the menu bar, which is the host's;
    /// the module applies it, because that is where the unbounded string is.
    public static func menuBarTitle(_ text: String) -> String? {
        let flattened = text.components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespaces)
        guard !flattened.isEmpty else { return nil }
        guard flattened.count > titleLimit else { return flattened }
        return String(flattened.prefix(titleLimit - 1)) + "…"
    }

    private static let titleLimit = 24

    /// Whether the chosen appearance should actually move right now.
    public static func spins(_ appearance: StatusAppearance,
                             now: Date, reduceMotion: Bool) -> Bool {
        guard !reduceMotion else { return false }
        // A countdown owns this ring while it runs. Reachable only because
        // `choose` ranks a countdown above a spin.
        guard appearance.timerProgress == nil else { return false }
        return (appearance.spinUntil ?? .distantPast) > now
    }

    /// Whether the once-a-second tick must run: a ring counts down, or a title
    /// carries text drawn from the clock. Modules emit only on a change, so
    /// neither moves without it.
    public static func wantsSecondTick(_ appearance: StatusAppearance) -> Bool {
        appearance.timerProgress != nil || appearance.title != nil
    }
}
