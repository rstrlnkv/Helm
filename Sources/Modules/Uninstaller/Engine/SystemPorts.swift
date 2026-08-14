import AppKit
import Foundation
import HelmRuntime

// MARK: - App listing

final class WorkspaceAppLister: AppLister {
    private let home: URL
    private let fs: FileSystemPort
    init(home: URL, fs: FileSystemPort) { self.home = home; self.fs = fs }

    private var searchDirs: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         home.appendingPathComponent("Applications"),
         URL(fileURLWithPath: "/Applications/Setapp"),
         home.appendingPathComponent("Applications/Setapp")]
    }

    func installedBundleIDs() -> Set<String> {
        var ids: Set<String> = []
        for dir in searchDirs {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { continue }
            for app in items where app.pathExtension == "app" {
                let info = app.appendingPathComponent("Contents/Info.plist")
                if let id = NSDictionary(contentsOf: info)?["CFBundleIdentifier"] as? String,
                   !id.isEmpty { ids.insert(id) }
            }
        }
        return ids
    }

    func isKnownToSystem(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// The listing above cannot answer this: `/Applications/Adobe Acrobat
    /// DC/Adobe Acrobat.app` is one folder past what it reads, and a second
    /// bundle declaring an id is the only evidence the scan has that the id
    /// does not belong to the app being removed. LaunchServices knows every
    /// copy it has ever seen, so `InstalledLocation` keeps the ones that are
    /// installed rather than merely present.
    /// LaunchServices rather than the listing, and not both: the listing is
    /// already read once per scan for `installedBundleIDs()`, and reading it a
    /// second time to group it by id would double that for an answer
    /// LaunchServices gives more completely — it registers `/Applications`
    /// itself, so a bundle there that it has never heard of does not arise.
    func installedPaths(forBundleID id: String) -> [String] {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
            .map(\.path)
            .filter { InstalledLocation.isInstalled(path: $0, home: home.path) }
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
    /// Full Disk Access case, which is every install (CLAUDE.md), and folded into
    /// `[]` it made the switch on the Leftovers tab say on over a Trash nothing
    /// could see. A Trash that is simply *not there* — a fresh account has none
    /// until something is deleted — is empty rather than nil, or the page would
    /// report a missing permission to somebody who has all of them.
    func trashedApps() -> [TrashedApp]? {
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
            let code = (error as NSError).code
            HelmLog.shared.warn(UninstallerEngine.moduleID,
                                "the Trash could not be read: \(code)")
            return code == NSFileReadNoSuchFileError ? [] : nil
        }
        return items
            .filter { $0.pathExtension == "app" }
            .compactMap { app in
                let info = app.appendingPathComponent("Contents/Info.plist")
                return TrashedAppIdentity.of(path: app.path,
                                             info: NSDictionary(contentsOf: info) as? [String: Any])
            }
    }

    func installedApps() -> [InstalledApp] {
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
                let info = app.appendingPathComponent("Contents/Info.plist")
                let dict = NSDictionary(contentsOf: info)
                guard let bundleID = dict?["CFBundleIdentifier"] as? String, !bundleID.isEmpty else { continue }
                if !SystemApp.isSystem(bundleID: bundleID), Self.leadsElsewhere(app, inside: folder) {
                    linked += 1
                    continue
                }
                let name = (dict?["CFBundleDisplayName"] as? String)
                    ?? (dict?["CFBundleName"] as? String)
                    ?? app.deletingPathExtension().lastPathComponent
                // Size 0: `appSizes()` fills these in afterwards, so the list
                // appears at once instead of after a walk of every bundle.
                out.append(InstalledApp(name: name, bundleID: bundleID,
                                        path: app.path, sizeBytes: 0))
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
    /// extension, and `NSDictionary(contentsOf:)` reads the *target's*
    /// `Info.plist` through it — so the row carried the real name and the real
    /// bundle id while `FileWeight.allocated` answered **0** bytes for it, and
    /// `RemovableScope.isRemovable` allowed the move. What `FileManager.trashItem`
    /// does with such a leaf, take the link or take the target, is a question this
    /// app has no answer to, and **both answers are defects**: one leaves the app
    /// installed with its containers gone under a banner saying it is in the
    /// Trash, the other breaks "the leaf is left unresolved on purpose"
    /// (ARCHITECTURE § Removal scope). So the offer is withdrawn rather than
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
    /// row that says «System» away from a person who can see the app in Finder.
    private static func leadsElsewhere(_ app: URL, inside folder: URL) -> Bool {
        app.resolvingSymlinksInPath().standardizedFileURL.path
            != folder.appendingPathComponent(app.lastPathComponent).path
    }

    /// Measured in parallel: the walks are independent, and one slow bundle
    /// (Xcode, 3.2 s here) otherwise holds up the other thirty-eight.
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] {
        let fs = self.fs
        var sizes: [String: Int] = [:]
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
    /// applications). Both callers here are off it: the scan runs inside
    /// `offTheCooperativePool`, and `quit` arrives on the transport's pool —
    /// while this very type is terminating applications, which is to say while
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

// MARK: - Factory

public struct UninstallerSystemPorts {
    public let fs = FMFileSystem()
    public let trash = FMTrash()
    public let running = WorkspaceRunningApps()
    public let apps: AppLister
    public init(home: URL) {
        self.apps = WorkspaceAppLister(home: home, fs: FMFileSystem())
    }
}

/// Both uninstaller checks go through the shared CLI in HelmRuntime.
public struct SystemExtensionLister: SystemExtensionPort {
    public init() {}
    /// `hostIdentifiersIfAnswered`, never the folded reader: a tool that did not
    /// run is not a Mac with no extensions on it, and this answer decides whether
    /// the failure sheet offers to open the Extensions pane.
    public func activeExtensionHosts() -> Set<String>? {
        SystemExtensionCLI.hostIdentifiersIfAnswered()
    }
    public func installedExtensions() -> [SystemExtensionInfo] { SystemExtensionCLI.installed() }
}
