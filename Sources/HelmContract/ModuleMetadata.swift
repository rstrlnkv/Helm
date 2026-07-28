public struct ModuleMetadata: Sendable {
    public let id: ModuleID
    public let name: String
    /// What the sidebar calls the module, where the column is fixed and a long
    /// name is cut off mid-word rather than wrapped. Defaults to `name`, which
    /// is what eight of the nine modules want; only the one named after a macOS
    /// pane with a compound name needs the short form, and macOS itself carries
    /// both ("Login Items & Extensions" in the pane, "Login Items" in a list).
    /// Everywhere else — the page header, the panel, the icon menu — uses the
    /// full name, because there the width is the content's to take.
    public let shortName: String
    public let summary: String
    public let sfSymbol: String
    public let permissions: [ModulePermission]
    public init(id: ModuleID, name: String, shortName: String? = nil, summary: String,
                sfSymbol: String, permissions: [ModulePermission] = []) {
        self.id = id; self.name = name; self.shortName = shortName ?? name
        self.summary = summary
        self.sfSymbol = sfSymbol; self.permissions = permissions
    }
}
