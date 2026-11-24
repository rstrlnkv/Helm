public struct ModuleMetadata: Sendable {
    public let id: ModuleID
    public let name: String
    /// What the sidebar and the panel call the module, where the column is fixed
    /// and a long name is cut off mid-word rather than wrapped. Defaults to `name`, which
    /// is what every module but one wants; only the one named after a macOS
    /// pane with a compound name needs the short form, and macOS itself carries
    /// both ("Login Items & Extensions" in the pane, "Login Items" in a list).
    /// Everywhere else — the page header, the icon menu — uses the full name,
    /// because there the width is the content's to take.
    public let shortName: String
    public let summary: String
    public let sfSymbol: String
    /// What the module uses if macOS grants it.
    public let permissions: [ModulePermission]
    /// The subset without which the module can do *nothing*.
    ///
    /// `permissions` answers a different question, what a module would use. A
    /// Full Disk module without the grant works and finds less; Layout without
    /// Accessibility does nothing. A sidebar mark drawn from `permissions` would
    /// sit on most rows and mean nothing.
    ///
    /// Empty by default, so a module that says nothing is never accused of
    /// being broken.
    public let inertWithout: [ModulePermission]
    /// The one thing this module offers to set up on a first launch, worded as
    /// the button that takes somebody there — or nothing, which is what every
    /// module but one says.
    ///
    /// **Here rather than in the tour**, where it would be a hand-written list
    /// of module ids in a target that cannot see the modules, with nothing
    /// failing the day it went stale. The tour is built from the descriptor.
    public let welcomeOffer: String?
    public init(id: ModuleID, name: String, shortName: String? = nil, summary: String,
                sfSymbol: String, permissions: [ModulePermission] = [],
                inertWithout: [ModulePermission] = [], welcomeOffer: String? = nil) {
        self.id = id; self.name = name; self.shortName = shortName ?? name
        self.summary = summary
        self.sfSymbol = sfSymbol; self.permissions = permissions
        self.inertWithout = inertWithout
        self.welcomeOffer = welcomeOffer
    }
}
