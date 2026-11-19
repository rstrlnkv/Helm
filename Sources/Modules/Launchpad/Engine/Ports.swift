import Foundation

/// One installed application as the latest catalog read found it. `id` is the bundle
/// identifier — the layout's only key; `path` is what a launch uses, and belongs to this read.
public struct CatalogApp: Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    /// The bundle's own `LSApplicationCategoryType`, raw (`public.app-category.music`), bounded; nil when it has none, an
    /// empty one or one that is not a string. Naming it for a person is the page's.
    public let category: String?

    init(id: String, name: String, path: String, category: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.category = category
    }
}

/// What a read of the installed applications found. `complete` is false when any directory
/// would not open or the walk stopped at the ceiling on apps, so a missing app may be one this
/// process could not see.
struct CatalogReading: Equatable, Sendable {
    let apps: [CatalogApp]
    let complete: Bool

    init(apps: [CatalogApp], complete: Bool) {
        self.apps = apps
        self.complete = complete
    }
}

/// The installed applications.
///
/// **Collapsed reasons.** A root that does not exist reads as empty and complete; a
/// directory that exists but would not open (`.refused`) makes `complete` false; an
/// application with no readable bundle identifier is skipped and counted in the log.
/// Duplicate ids collapse to one entry. A change in the installed set is seen by a
/// `read()`; `observeChanges` says when to ask again.
protocol AppCatalogPort: Sendable {
    func read() -> CatalogReading

    /// The bundle identifier of the application at `path`, read the way `read()` reads it.
    /// **nil collapses** a bundle that is not there, a property list that will not open or
    /// parse, one over the ceiling, and one with no identifier or an empty one: a caller that
    /// needs the reason has none to ask for, and takes every one of them as "not that app".
    func bundleID(atPath path: String) -> String?

    /// Calls `onChange` (on a queue of its own) when something in the watched folders may
    /// have changed an application, for as long as the returned token is held. Dropping the
    /// token ends it. A watch that could not start is logged and never calls: the next
    /// `read()` is then the only way to learn of a change.
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject
}

/// Opens an application. Every refusal — the system said no, nothing there to open — is `false`.
protocol AppLauncherPort: Sendable {
    func open(_ url: URL) async -> Bool
}

/// What a launch came to. `gone`: a complete read of the installed apps no longer holds the
/// id, or the bundle at its path answers another id. `unreadable`: the read was incomplete and
/// the id is not in it, so it may be an app this process could not see. `failed`: the system
/// refused to open it.
public enum LaunchOutcome: Equatable, Sendable {
    case launched, gone, unreadable, failed
}
