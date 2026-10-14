import Foundation

public struct StatusAppearance: Equatable, Sendable {
    public var tintToken: String?   // palette token, nil = default (white ring)
    /// Optional menu-bar glyph override (MenuBarIconStyle rawValue). nil = keep the
    /// user's global shape; set by a module that wants a distinct active-state icon.
    public var iconStyle: String?
    /// 0…1 remaining fraction of a timed session; the host draws the ring as a
    /// countdown arc. nil = no countdown arc.
    public var timerProgress: Double?
    /// The moment the countdown shown in the menu bar reaches zero. nil = this
    /// appearance claims no countdown by its deadline; one that carries a
    /// `timerProgress` still counts down by its arc.
    ///
    /// `StatusPlan.choose` reads it as "counting down" however the countdown is
    /// drawn, by a ring (`timerProgress`) or by text (`title`). A text-only
    /// countdown carries no progress, so an appearance that draws one and
    /// leaves this field nil is not counting down to `choose`, and another
    /// module's spin takes its remaining time off the bar.
    ///
    /// Set it only while the countdown is visible, by ring or by text: a
    /// session nobody draws must not claim the icon, because that would
    /// silently suppress another module's spin.
    ///
    /// A moment and not a duration, for the same reason as `spinUntil`: the
    /// host reads this struct when it redraws and receives no events, so a
    /// moment already past counts nothing down however often it is asked.
    public var countdownUntil: Date?
    /// Short text shown next to the icon (e.g. a countdown). nil = icon only.
    public var title: String?
    /// Spin the ring until this moment. nil = still.
    ///
    /// Level-triggered, like everything else here: the host reads this struct
    /// when it redraws and receives no events, so "a thing just happened" would
    /// be missed or replayed depending on timing. "Spin until T" answers
    /// correctly however often it is asked.
    public var spinUntil: Date?
    /// The colour of the spin, which is not a claim on the icon.
    ///
    /// Deliberately not `tintToken`: that field is what `StatusPlan.choose`
    /// reads to decide who owns the menu bar *between* moments, and a module
    /// that only wants its own second of animation coloured must not thereby
    /// become the module that owns the icon all day. `VPNDescriptor` records
    /// "no tint, ever" for the same reason and that decision still stands.
    public var spinTintToken: String?
    public init(tintToken: String? = nil, iconStyle: String? = nil,
                timerProgress: Double? = nil, countdownUntil: Date? = nil,
                title: String? = nil,
                spinUntil: Date? = nil, spinTintToken: String? = nil) {
        self.tintToken = tintToken
        self.iconStyle = iconStyle
        self.timerProgress = timerProgress
        self.countdownUntil = countdownUntil
        self.title = title
        self.spinUntil = spinUntil
        self.spinTintToken = spinTintToken
    }
    public static let inactive = StatusAppearance()
}
