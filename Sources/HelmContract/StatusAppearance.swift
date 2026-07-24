public struct StatusAppearance: Equatable, Sendable {
    public var tintToken: String?   // palette token, nil = default (white ring)
    public var badge: String?       // optional SF Symbol badge, unused in v1
    public init(tintToken: String? = nil, badge: String? = nil) {
        self.tintToken = tintToken; self.badge = badge
    }
    public static let inactive = StatusAppearance()
}
