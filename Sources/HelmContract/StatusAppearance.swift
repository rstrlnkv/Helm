public struct StatusAppearance: Equatable, Sendable {
    public var tintToken: String?   // palette token, nil = default (white ring)
    /// Optional menu-bar glyph override (MenuBarIconStyle rawValue). nil = keep the
    /// user's global shape; set by a module that wants a distinct active-state icon.
    public var iconStyle: String?
    public init(tintToken: String? = nil, iconStyle: String? = nil) {
        self.tintToken = tintToken
        self.iconStyle = iconStyle
    }
    public static let inactive = StatusAppearance()
}
