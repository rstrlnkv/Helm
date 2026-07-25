import AppKit
import Foundation

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
                out.append(InstalledApp(name: name, bundleID: bundleID,
                                        path: app.path, sizeBytes: fs.size(app)))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Filesystem

public struct FMFileSystem: FileSystemPort {
    public init() {}

    public func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    public func size(_ url: URL) -> Int {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: keys)
            return v?.totalFileAllocatedSize ?? 0
        }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total = 0
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: keys)
            if v?.isRegularFile == true { total += v?.totalFileAllocatedSize ?? 0 }
        }
        return total
    }

    public func glob(_ pattern: URL) -> [URL] {
        let dir = pattern.deletingLastPathComponent()
        let pat = pattern.lastPathComponent
        guard pat.contains("*") else { return exists(pattern) ? [pattern] : [] }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return items
            .filter { GlobMatch.matches($0, pattern: pat) }
            .map { dir.appendingPathComponent($0) }
    }

    public func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
            .map { url.appendingPathComponent($0) } ?? []
    }
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
    public func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
    public func quit(bundleID: String, force: Bool) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            if force { app.forceTerminate() } else { app.terminate() }
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


/// Reads `systemextensionsctl list`; there is no public API for this, and the
/// tool ships with every macOS install. Parsing lives in SystemExtensionParser.
public struct SystemExtensionLister: SystemExtensionPort {
    public init() {}

    private func listOutput() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return "" }
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    public func activeExtensionHosts() -> Set<String> {
        SystemExtensionParser.hostIdentifiers(listOutput())
    }

    public func installedExtensions() -> [SystemExtensionInfo] {
        SystemExtensionParser.parse(listOutput())
    }
}
