import Foundation
import HelmRuntime

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
    public let documents: URL

    /// `documents` defaults to the home's own, so a test that names a scratch
    /// home has a Documents inside it and never the person's.
    public init(home: URL, desktop: URL, documents: URL? = nil) {
        self.home = home
        self.desktop = desktop
        self.documents = documents ?? home.appendingPathComponent("Documents", isDirectory: true)
    }

    /// A temporary home of this process's own under a test runner, so a suite
    /// run never lands in the person's Desktop or Documents — the rule
    /// `TestProcess` exists for, which `StoresOfTheirsAskIfThisIsATestTests`
    /// holds for every site that resolves one of their folders. In the app,
    /// `FileManager`'s own lookup.
    ///
    /// Resolved once, like `HelmSupport.directory`: asking for the temporary one
    /// sweeps `$TMPDIR` for abandoned directories every time.
    public static let system: ScreenshotsLocations = {
        if TestProcess.isRunning {
            let home = TestScratch(prefix: "helm-screenshots-home-").directory()
            let locations = ScreenshotsLocations(
                home: home, desktop: home.appendingPathComponent("Desktop", isDirectory: true))
            // The scratch is named, not made, and the folders are judged by
            // existing: they stand in for ones the person has.
            for folder in [locations.desktop, locations.documents] {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            return locations
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Desktop", isDirectory: true)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Documents", isDirectory: true)
        return ScreenshotsLocations(home: home, desktop: desktop, documents: documents)
    }()
}
