import AppKit
import Foundation
import HelmRuntime

// MARK: - App listing

public final class WorkspaceAppLister: AppLister {
    private let home: URL
    private let fs: FileSystemPort
    public init(home: URL, fs: FileSystemPort) { self.home = home; self.fs = fs }

    private var searchDirs: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         home.appendingPathComponent("Applications"),
         URL(fileURLWithPath: "/Applications/Setapp"),
         home.appendingPathComponent("Applications/Setapp")]
    }

    public func installedBundleIDs() -> Set<String> {
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

    public func isKnownToSystem(bundleID: String) -> Bool {
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
    public func installedPaths(forBundleID id: String) -> [String] {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
            .map(\.path)
            .filter { InstalledLocation.isInstalled(path: $0, home: home.path) }
    }

    public func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [InstalledApp] = []
        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for app in items where app.pathExtension == "app" {
                guard !seen.contains(app.path) else { continue }
                seen.insert(app.path)
                let info = app.appendingPathComponent("Contents/Info.plist")
                let dict = NSDictionary(contentsOf: info)
                guard let bundleID = dict?["CFBundleIdentifier"] as? String, !bundleID.isEmpty else { continue }
                let name = (dict?["CFBundleDisplayName"] as? String)
                    ?? (dict?["CFBundleName"] as? String)
                    ?? app.deletingPathExtension().lastPathComponent
                // Size 0: `appSizes()` fills these in afterwards, so the list
                // appears at once instead of after a walk of every bundle.
                out.append(InstalledApp(name: name, bundleID: bundleID,
                                        path: app.path, sizeBytes: 0))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Measured in parallel: the walks are independent, and one slow bundle
    /// (Xcode, 3.2 s here) otherwise holds up the other thirty-eight.
    public func appSizes(_ apps: [InstalledApp]) -> [String: Int] {
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
    public func activeExtensionHosts() -> Set<String> { SystemExtensionCLI.hostIdentifiers() }
    public func installedExtensions() -> [SystemExtensionInfo] { SystemExtensionCLI.installed() }
}
