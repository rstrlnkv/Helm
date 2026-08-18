public struct ModuleMetadata: Sendable {
    public let id: ModuleID
    public let name: String
    /// What the sidebar calls the module, where the column is fixed and a long
    /// name is cut off mid-word rather than wrapped. Defaults to `name`, which
    /// is what every module but one wants; only the one named after a macOS
    /// pane with a compound name needs the short form, and macOS itself carries
    /// both ("Login Items & Extensions" in the pane, "Login Items" in a list).
    /// Everywhere else — the page header, the panel, the icon menu — uses the
    /// full name, because there the width is the content's to take.
    public let shortName: String
    public let summary: String
    public let sfSymbol: String
    /// What the module uses if macOS grants it.
    public let permissions: [ModulePermission]
    /// The subset without which the module can do *nothing*.
    ///
    /// `permissions` answers a different question — what a module would use —
    /// and the sidebar was reading it as if it answered this one. That marked
    /// seven rows with «Enabled, but macOS is withholding the access it
    /// needs»: true of Layout, which is inert without Accessibility, and false
    /// of the four Full Disk modules, which work and find less; false of Keep
    /// Awake, which holds a power assertion and never touches Accessibility
    /// unless the pointer nudge is switched on, and that ships off. A mark on
    /// 78% of the rows is wallpaper, and it cost the one row where it was
    /// exactly right.
    ///
    /// Empty by default, so a module that says nothing is never accused of
    /// being broken.
    public let inertWithout: [ModulePermission]
    /// The one thing this module offers to set up on a first launch, worded as
    /// the button that takes somebody there — or nothing, which is what every
    /// module but one says.
    ///
    /// **Here rather than in the tour**, which is where a list of «modules with
    /// something worth setting up» would have been: a tenth hand-written list of
    /// module ids, in a target that cannot see the modules, with nothing failing
    /// on the day it went stale. The descriptor already says the module's name
    /// and its summary and the tour is built from those; this is one more
    /// sentence of the same kind.
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
