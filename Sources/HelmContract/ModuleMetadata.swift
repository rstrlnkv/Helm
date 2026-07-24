public struct ModuleMetadata: Sendable {
    public let id: ModuleID
    public let name: String
    public let summary: String
    public let sfSymbol: String
    public let permissions: [ModulePermission]
    public init(id: ModuleID, name: String, summary: String,
                sfSymbol: String, permissions: [ModulePermission] = []) {
        self.id = id; self.name = name; self.summary = summary
        self.sfSymbol = sfSymbol; self.permissions = permissions
    }
}
