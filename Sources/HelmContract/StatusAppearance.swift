import Foundation

public struct StatusAppearance: Equatable, Sendable {
    public var tintToken: String?   // palette token, nil = default (white ring)
    /// Optional menu-bar glyph override (MenuBarIconStyle rawValue). nil = keep the
    /// user's global shape; set by a module that wants a distinct active-state icon.
    public var iconStyle: String?
    /// 0…1 remaining fraction of a timed session; the host draws the ring as a
    /// countdown arc. nil = no timer running.
    public var timerProgress: Double?
    /// Short text shown next to the icon (e.g. a countdown). nil = icon only.
    public var title: String?
    /// Spin the ring until this moment. nil = still.
    ///
    /// Level-triggered, like everything else here: the host reads this struct
    /// when it redraws and receives no events, so "a thing just happened" would
    /// be missed or replayed depending on timing. "Spin until T" answers
    /// correctly however often it is asked.
    public var spinUntil: Date?
    public init(tintToken: String? = nil, iconStyle: String? = nil,
                timerProgress: Double? = nil, title: String? = nil,
                spinUntil: Date? = nil) {
        self.tintToken = tintToken
        self.iconStyle = iconStyle
        self.timerProgress = timerProgress
        self.title = title
        self.spinUntil = spinUntil
    }
    public static let inactive = StatusAppearance()
}
