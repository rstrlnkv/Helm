import Foundation

/// One installed application as the latest catalog read found it. `id` is the bundle
/// identifier — the layout's only key; `path` is what a launch uses, and belongs to this read.
public struct CatalogApp: Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String

    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

/// What a read of the installed applications found. `complete` is false when any directory
/// would not open or the walk stopped at the ceiling on apps, so a missing app may be one this
/// process could not see.
public struct CatalogReading: Equatable, Sendable {
    public let apps: [CatalogApp]
    public let complete: Bool

    public init(apps: [CatalogApp], complete: Bool) {
        self.apps = apps
        self.complete = complete
    }
}

/// The installed applications.
///
/// **Collapsed reasons.** A root that does not exist reads as empty and complete; a
/// directory that exists but would not open (`.refused`) makes `complete` false; an
/// application with no readable bundle identifier is skipped and counted in the log.
/// Duplicate ids collapse to one entry. **No change channel:** a change in the installed
/// set is seen only on the next `read()`; the UI pass owns watching.
public protocol AppCatalogPort: Sendable {
    func read() -> CatalogReading
}
