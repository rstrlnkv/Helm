import AppKit
import CoreServices
import Foundation
import HelmRuntime

// MARK: - App listing

public final class WorkspaceAppLister: AppLister {
    private let home: URL
    private let fs: FileSystemPort
    public init(home: URL, fs: FileSystemPort) { self.home = home; self.fs = fs }

    private var searchDirs: [URL] {
        AppRemovability.folders(home: home.path).map { URL(fileURLWithPath: $0) }
    }

    public func installedBundleIDs() -> Set<String> {
        PropertyListFile.installedBundleIDs(home: home.path)
    }

    /// The `CFBundleIdentifier` in a bundle's `Info.plist`, nil when unreadable.
    /// A bulk read of file contents: the pool goes inside the iteration, so it
    /// is here, one per call (Architecture/ModulePattern.md § Module pattern).
    static func bundleID(forAppAt path: String) -> String? {
        autoreleasepool {
            PropertyListFile.infoPlist(ofBundleAt: URL(fileURLWithPath: path))?["CFBundleIdentifier"] as? String
        }
    }

    public func isKnownToSystem(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Where else an id is installed: a second bundle declaring it is the only
    /// evidence that the id does not belong to the app being removed. The
    /// listing keeps ids, not paths, and does not reach deep or nested copies;
    /// LaunchServices knows every copy it has seen, and `InstalledLocation`
    /// keeps the ones that are installed rather than merely present.
    public func installedPaths(forBundleID id: String) -> [String] {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
            .map(\.path)
            .filter { InstalledLocation.isInstalled(path: $0, home: home.path) }
    }

    /// Spotlight's own answer through the metadata API, in this process. See the
    /// port for which reasons read as `nil`.
    ///
    /// Only a date Spotlight itself recorded. On a volume it does not index, the
    /// API answers `kMDItemLastUsedDate` with the file's modification date, and
    /// every app would read "Opened N years ago". The item's attribute names
    /// list the attribute only when it is stored, which tells the two apart.
    public func lastOpened(path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString),
              let names = MDItemCopyAttributeNames(item) as? [String],
              names.contains(kMDItemLastUsedDate as String) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// What a failed read of the Trash means: no Trash at all is an empty one and
    /// says nothing, anything else is a refusal that is logged and answered `nil`.
    static func trashReadFailure(code: Int) -> (warning: String?, apps: [TrashedApp]?) {
        code == NSFileReadNoSuchFileError
            ? (nil, [])
            : ("the Trash could not be read: \(code)", nil)
    }

    /// The user's own Trash only: an app is rarely installed on and deleted from
    /// an external disk, and each volume's `.Trashes` is a separate protected read.
    ///
    /// An entry that is not a readable app bundle yields nothing rather than an
    /// error: the question is only whether there is anything to offer.
    ///
    /// A read Helm was not allowed to make is `nil`, not empty: that is the Full
    /// Disk Access case, every local install
    /// (Architecture/Release.md § Signing and grants), and the switch must not
    /// say on over a Trash nothing can see. A Trash that is not there (a fresh
    /// account) is empty, or the page would report a missing permission.
    public func trashedApps() -> [TrashedApp]? {
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        let items: [URL]
        do {
            items = try FileManager.default.contentsOfDirectory(
                at: trash, includingPropertiesForKeys: nil)
        } catch {
            // A failed read is logged so it is not the silence of an empty
            // Trash. The path is the user's home and is not written.
            let refusal = Self.trashReadFailure(code: (error as NSError).code)
            if let warning = refusal.warning {
                HelmLog.shared.warn(UninstallerEngine.moduleID, warning)
            }
            return refusal.apps
        }
        return items
            .filter { $0.pathExtension == "app" }
            .compactMap { app in
                // Inside the iteration, and only the extracted identity leaves it
                // (Architecture/ModulePattern.md § Module pattern).
                autoreleasepool {
                    TrashedAppIdentity.of(path: app.path, info: PropertyListFile.infoPlist(ofBundleAt: app))
                }
            }
    }

    /// One `opendir`, so the press that asks reads no `Info.plist` on main. A
    /// missing Trash lists as empty and stays readable, as in `trashedApps()`.
    public func trashIsReadable() -> Bool {
        DirectoryListing.contents(of: home.appendingPathComponent(".Trash", isDirectory: true)) != .refused
    }

    public func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [InstalledApp] = []
        // Counted, so a missing row is explained; not named, since a bundle id
        // names somebody's habits.
        var linked = 0
        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            // Once per folder: `resolvingSymlinksInPath` is a `realpath` each time.
            let folder = dir.resolvingSymlinksInPath().standardizedFileURL
            for app in items where app.pathExtension == "app" {
                guard !seen.contains(app.path) else { continue }
                seen.insert(app.path)
                // One `Info.plist` per bundle: the pool goes inside the iteration and
                // only the two Strings leave it (Architecture/ModulePattern.md § Module pattern).
                let plist: (bundleID: String, name: String?)? = autoreleasepool {
                    let dict = PropertyListFile.infoPlist(ofBundleAt: app)
                    guard let bundleID = dict?["CFBundleIdentifier"] as? String, !bundleID.isEmpty else { return nil }
                    return (bundleID, (dict?["CFBundleDisplayName"] as? String)
                        ?? (dict?["CFBundleName"] as? String))
                }
                guard let bundleID = plist?.bundleID else { continue }
                if !SystemApp.isSystem(bundleID: bundleID), Self.leadsElsewhere(app, inside: folder) {
                    linked += 1
                    continue
                }
                let name = plist?.name ?? app.deletingPathExtension().lastPathComponent
                // No size: `appSizes()` fills these in afterwards, so the list
                // appears at once instead of after a walk of every bundle.
                out.append(InstalledApp(name: name, bundleID: bundleID, path: app.path))
            }
        }
        if linked > 0 {
            HelmLog.shared.info(UninstallerEngine.moduleID,
                                "\(linked) linked bundle(s) not offered: what a move would take, "
                                + "the link or the app behind it, is not a question this app answers")
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Whether a listed entry leads somewhere other than where it is spelled.
    ///
    /// A linked `.app` lists like a bundle and reads the target's `Info.plist`,
    /// with no size of its own, and the scope allows its move. Whether
    /// `FileManager.trashItem` then takes the link or the target, both are
    /// defects: the app stays installed with its containers gone, or the leaf is
    /// not left alone (Architecture/TheGates.md § The gates). So the offer is
    /// withdrawn rather than guessed at. Apps arrive as links from nix-darwin,
    /// some cask layouts and by hand.
    ///
    /// Both sides are resolved, because `resolvingSymlinksInPath()` rewrites
    /// `/private/var/…` to `/var/…` and an unresolved folder would make every
    /// entry "lead elsewhere". A link at the folder itself is not asked here:
    /// `RemovableScope.partition` resolves ancestors before judging a path.
    ///
    /// The caller exempts a `com.apple.` bundle: `/Applications/Safari.app` is
    /// itself a link into the Cryptexes. Its row has no checkbox and `setChecked`
    /// refuses the id (`SystemApp`), so there is no offer to withdraw, only the
    /// «System app» row to keep.
    static func leadsElsewhere(_ app: URL, inside folder: URL) -> Bool {
        app.resolvingSymlinksInPath().standardizedFileURL.path
            != folder.appendingPathComponent(app.lastPathComponent).path
    }

    /// Measured in parallel: the walks are independent, and one slow bundle
    /// would otherwise hold up the rest.
    public func appSizes(_ apps: [InstalledApp]) -> [String: Int] {
        let fs = self.fs
        // `nonisolated(unsafe)`: the compiler cannot see `lock`, and the shape it
        // objects to is the one wanted — one write per index under the lock, and
        // the read below runs after `concurrentPerform` has joined.
        nonisolated(unsafe) var sizes: [String: Int] = [:]
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let app = apps[index]
            let size = fs.size(URL(fileURLWithPath: app.path))
            // Keyed by path: two copies of one app share a bundle id, and each
            // row needs its own size.
            lock.lock(); sizes[app.path] = size; lock.unlock()
        }
        return sizes
    }
}

// MARK: - Filesystem

public struct FMFileSystem: FileSystemPort {
    public init() {}

    public func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// One measurement for the app, and a hard link counted once.
    public func size(_ url: URL) -> Int { FileWeight.allocated(of: url) }

    public func glob(_ pattern: URL) -> [URL] {
        let dir = pattern.deletingLastPathComponent()
        let pat = pattern.lastPathComponent
        guard pat.contains("*") else { return exists(pattern) ? [pattern] : [] }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return items
            .filter { GlobMatch.matches($0, pattern: pat) }
            .map { dir.appendingPathComponent($0) }
    }

    public func children(of url: URL) -> [URL] { DirectoryListing.children(of: url) }
}

// MARK: - Trash

public struct FMTrash: TrashPort {
    public init() {}
    public func trashItem(_ url: URL) -> TrashOutcome {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return .success
        } catch {
            let ns = error as NSError
            return TrashOutcome(succeeded: false, errorCode: ns.code,
                                message: ns.localizedDescription)
        }
    }
}

// MARK: - Running apps

public struct WorkspaceRunningApps: RunningAppsPort {
    public init() {}

    /// `runningApplications(withBundleIdentifier:)` reads AppKit's own mutable
    /// list, which must not be read off the main thread
    /// (Architecture/RunningOtherPrograms.md § Running applications), and every
    /// caller here runs off it, while this type terminates applications.
    ///
    /// The hop is at the port, the boundary, so no caller can forget it.
    private func onMain<T: Sendable>(_ body: @MainActor @Sendable () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(body) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }

    public func isRunning(bundleID: String) -> Bool {
        onMain { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    }

    public func quit(bundleID: String, force: Bool) {
        onMain {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                if force { app.forceTerminate() } else { app.terminate() }
            }
        }
    }
}

/// The one question, `activeExtensionHosts`, goes through the shared CLI in HelmRuntime.
public struct SystemExtensionLister: SystemExtensionPort {
    public init() {}
    /// `hostIdentifiersIfAnswered`, never the folded reader: a tool that did not
    /// run is not a Mac with no extensions, and this answer decides whether the
    /// failure sheet offers the Extensions pane.
    public func activeExtensionHosts() -> Set<String>? {
        SystemExtensionCLI.hostIdentifiersIfAnswered()
    }
}

/// The file probe `PermissionCheck` reads for the settings pages.
public struct FullDiskAccessProbe: FullDiskAccessPort {
    public init() {}
    public func fullDiskAccess() -> PermissionState? { PermissionCheck.currentFullDiskAccess() }
}
