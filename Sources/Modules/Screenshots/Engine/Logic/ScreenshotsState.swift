import Foundation

/// Everything the engine tells the settings page.
///
/// What the page cannot read for itself because it lives outside Helm: the
/// folder macOS saves into (validated), and which of the system's screenshot
/// boxes are ticked. Settings themselves are the page's own store, and a frame
/// is never here.
public struct ScreenshotsState: Codable, Equatable, Sendable {
    /// The folder pictures go to, as a path.
    public var folder: String
    /// Set when macOS names a folder Helm cannot use, and the path above is the
    /// Desktop instead.
    public var folderRefused: SaveFolderRefusal?
    public var boxes: [SystemBoxReading]

    public init(folder: String, folderRefused: SaveFolderRefusal?, boxes: [SystemBoxReading]) {
        self.folder = folder
        self.folderRefused = folderRefused
        self.boxes = boxes
    }

    /// Before the first reading: nothing known, which is `unknown` and not `on`.
    public static let unread = ScreenshotsState(
        folder: "", folderRefused: nil,
        boxes: SystemShortcuts.boxes(from: .unreadable))
}

/// Where the user's own folders are. An argument rather than a read of the
/// process's home, so a test points the whole module at a scratch directory.
public struct ScreenshotsLocations: Sendable {
    public let home: URL
    public let desktop: URL

    public init(home: URL, desktop: URL) {
        self.home = home
        self.desktop = desktop
    }

    public static var system: ScreenshotsLocations {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Desktop", isDirectory: true)
        return ScreenshotsLocations(home: home, desktop: desktop)
    }
}
