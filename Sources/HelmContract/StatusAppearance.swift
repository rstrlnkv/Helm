public struct StatusAppearance: Equatable, Sendable {
    public var tintToken: String?   // palette token, nil = default (white ring)
    /// Optional menu-bar glyph override (MenuBarIconStyle rawValue). nil = keep the
    /// user's global shape; set by a module that wants a distinct active-state icon.
    public var iconStyle: String?
    /// 0…1 remaining fraction of a timed session; the host draws the ring as a
    /// countdown arc. nil = no timer running.
    public var timerProgress: Double?
    public init(tintToken: String? = nil, iconStyle: String? = nil, timerProgress: Double? = nil) {
        self.tintToken = tintToken
        self.iconStyle = iconStyle
        self.timerProgress = timerProgress
    }
    public static let inactive = StatusAppearance()
}
