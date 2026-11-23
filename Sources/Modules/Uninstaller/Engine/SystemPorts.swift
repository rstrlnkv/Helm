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
    /// is here, one per call (ARCHITECTURE.md § Module pattern).
    static func bundleID(forAppAt path: String) -> String? {
        autoreleasepool {
            PropertyListFile.infoPlist(ofBundleAt: URL(fileURLWithPath: path))?["CFBundleIdentifier"] as? String
        }
    }

    public func isKnownToSystem(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Where else an id is installed: a second bundle declaring it is the only
    /// evidence the scan has that the id does not belong to the app being
    /// removed. The listing above cannot answer this: it keeps ids, not the
    /// paths that declared them, and it stops at two folders below a root and
    /// never enters a bundle, so a copy deeper than that, or inside another
    /// bundle's `Contents`, is not in it. LaunchServices knows every copy it
    /// has ever seen, so `InstalledLocation` keeps the ones that are installed
    /// rather than merely present.
    /// LaunchServices rather than the listing, and not both: grouping the
    /// listing by id would be a second walk of every bundle's `Info.plist` for
    /// an answer LaunchServices gives more completely.
    public func installedPaths(forBundleID id: String) -> [String] {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
            .map(\.path)
            .filter { InstalledLocation.isInstalled(path: $0, home: home.path) }
    }

    /// Spotlight's own answer through the metadata API, in this process — no
    /// `mdls`, no other program. See the port for which reasons read as `nil`.
    ///
    /// **Only a date Spotlight itself recorded.** On a volume it does not index
    /// the API still answers `kMDItemLastUsedDate` — with the file's modification
    /// date, synthesised on the spot — and every app there would read "Opened N
    /// years ago" with N the age of the install. The two are told apart by the
    /// item's attribute names, which list the attribute only when it is stored.
    /// Measured on this Mac: 93 bundles under `/Applications` and
    /// `/System/Applications`, the attribute answered a date for 53 and was in
    /// the name list for the same 53; on an APFS volume with `mdutil -i off` a
    /// copy of Calculator with its mtime set to 2020-01-02 answered that mtime
    /// and its names (15) did not carry the attribute.
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

    /// The user's own Trash only. Per-volume `/Volumes/*/.Trashes/<uid>` is left
    /// alone: an app is rarely installed on and deleted from an external disk, and
    /// each of those is a separate protected read.
    ///
    /// Something in there that is not a readable app bundle — a broken download, a
    /// folder somebody named `.app` — yields nothing rather than an error. There is
    /// no failure to report to anyone: the question is whether there is anything to
    /// offer, and the answer is no.
    ///
    /// **A read Helm was not allowed to make is `nil`, not empty.** That is the
    /// Full Disk Access case, which is every local install (ARCHITECTURE.md § Signing and grants), and folded into
    /// `[]` it made the switch on the Leftovers tab say on over a Trash nothing
    /// could see. A Trash that is simply *not there* — a fresh account has none
    /// until something is deleted — is empty rather than nil, or the page would
    /// report a missing permission to somebody who has all of them.
    public func trashedApps() -> [TrashedApp]? {
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        let items: [URL]
        do {
            items = try FileManager.default.contentsOfDirectory(
                at: trash, includingPropertiesForKeys: nil)
        } catch {
            // A read that failed and a Trash with nothing in it are the same
            // silence to whoever opens the log, and they want different answers:
            // the first is usually Full Disk Access, which every install takes
            // away again. The path is the user's home and is not written.
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
                // (ARCHITECTURE.md § Module pattern).
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
        // Counted rather than named: a bundle id names somebody's habits, and a
        // row that is missing with nothing anywhere saying why reads as a folder
        // Helm could not see.
        var linked = 0
        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            // Once for the folder, not once per bundle: where the folder itself
            // leads is one fact about the listing, and `resolvingSymlinksInPath`
            // is a `realpath` each time it is asked.
            let folder = dir.resolvingSymlinksInPath().standardizedFileURL
            for app in items where app.pathExtension == "app" {
                guard !seen.contains(app.path) else { continue }
                seen.insert(app.path)
                // One `Info.plist` per bundle: the pool goes inside the iteration and
                // only the two Strings leave it (ARCHITECTURE.md § Module pattern).
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
    /// **Measured**, in a scratch directory: a symlink named `Linked.app` pointing
    /// at a real 3 MB bundle is returned by `contentsOfDirectory`, has the `.app`
    /// extension, and `PropertyListFile.infoPlist(ofBundleAt:)` reads the *target's*
    /// `Info.plist` through it — so the row carried the real name and the real
    /// bundle id while `FileWeight.allocated` answered **0** bytes for it, and
    /// `RemovableScope.isRemovable` allowed the move. What `FileManager.trashItem`
    /// does with such a leaf, take the link or take the target, is a question this
    /// app has no answer to, and **both answers are defects**: one leaves the app
    /// installed with its containers gone under a banner saying it is in the
    /// Trash, the other breaks "leaves the leaf alone"
    /// (ARCHITECTURE.md § The gates). So the offer is withdrawn rather than
    /// guessed at. Who has one: anyone whose apps arrive as links — nix-darwin,
    /// some cask layouts, hand-made links.
    ///
    /// **Both sides are resolved, and that is not a shortcut** — it is what
    /// `ScanRoot.resolve` records one target over: `resolvingSymlinksInPath()`
    /// rewrites `/private/var/…` to `/var/…`, so a folder compared against its own
    /// unresolved spelling answers "this leads somewhere else" for every entry in
    /// any temporary tree on this machine. What is left is the question that
    /// matters here — does *this entry* lead out of the folder it was listed in.
    /// The ancestor case, a link at `/Applications` redirecting everything under it
    /// without any single entry being a link, is not answered here on purpose: it
    /// is one question about the folder rather than one per row, and the removal
    /// gate already refuses what it leads to, since `RemovableScope.partition`
    /// resolves a path's ancestors before judging it.
    ///
    /// The caller exempts a `com.apple.` bundle, and that is not a courtesy:
    /// **measured on this Mac, `/Applications/Safari.app` is itself a link**, into
    /// `/System/Volumes/Preboot/Cryptexes/App/…`. Its row carries no checkbox and
    /// `setChecked` refuses the id (`SystemApp`), so it is not an offer to remove
    /// anything and there is nothing to withdraw — dropping it would only take the
    /// row that says «System app» away from a person who can see the app in Finder.
    static func leadsElsewhere(_ app: URL, inside folder: URL) -> Bool {
        app.resolvingSymlinksInPath().standardizedFileURL.path
            != folder.appendingPathComponent(app.lastPathComponent).path
    }

    /// Measured in parallel: the walks are independent, and one slow bundle
    /// (Xcode, 3.2 s here) otherwise holds up the other thirty-eight.
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
            // Keyed by path. Two copies of one app share a bundle id, so the
            // second write overwrote the first and which size survived was
            // decided by `concurrentPerform` — a race. Both rows then showed
            // one number and "will free" was wrong about one of them.
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
    /// list of running applications, and reading it off the main thread is what
    /// killed the VPN engine over four releases (ARCHITECTURE.md § Running
    /// applications). All callers here are off it: the scan, each
    /// quit and each poll of `waitUntilGone` run inside `offTheCooperativePool`
    /// — while this very type is terminating applications, which is to say while
    /// that list is being mutated.
    ///
    /// The hop lives here rather than at the call sites because this is the
    /// boundary: anything that reaches AppKit through this port gets the rule
    /// for free, and a third caller cannot forget it. One hop per scan — the
    /// scan is of one application, not a list.
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
    /// run is not a Mac with no extensions on it, and this answer decides whether
    /// the failure sheet offers to open the Extensions pane.
    public func activeExtensionHosts() -> Set<String>? {
        SystemExtensionCLI.hostIdentifiersIfAnswered()
    }
}

/// The file probe `PermissionCheck` reads for the settings pages.
public struct FullDiskAccessProbe: FullDiskAccessPort {
    public init() {}
    public func fullDiskAccess() -> PermissionState? { PermissionCheck.currentFullDiskAccess() }
}
