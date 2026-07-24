public struct StatusAppearance: Equatable, Sendable {
    public var tintToken: String?   // palette token, nil = default (white ring)
    public init(tintToken: String? = nil) {
        self.tintToken = tintToken
    }
    public static let inactive = StatusAppearance()
}
