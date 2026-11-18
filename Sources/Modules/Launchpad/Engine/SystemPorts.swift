import AppKit
import Foundation
import HelmRuntime

/// **The installed applications, read off three fixed folders.**
///
/// `/Applications`, `~/Applications`, `/System/Applications`, in that precedence. Safari is
/// not a fourth root: on this macOS `/Applications/Safari.app` is a symlink into
/// `/System/Cryptexes/App/System/Applications`, and a symlinked `.app` is accepted.
///
/// An entry with the extension `app` is an application and is never descended into; a plain,
/// non-symlink, non-hidden folder with no extension is descended into to `LaunchpadLimits.maxDepth` levels
/// (judged by name and one `lstat`, never by reading what is in it); symlinked folders are not followed.
/// One id found twice is one app: the earlier root wins, then the smallest path. A walk the
/// `LaunchpadLimits.maxApps` ceiling stopped, like a folder that would not open, is not `complete`.
/// Names are the one Finder shows: the bundle's localized display name in the person's language,
/// else `Info.plist` (display name, then bundle name), else the bundle's file name.
struct FileSystemAppCatalog: AppCatalogPort {
    private let roots: [URL]

    init(roots: [URL] = FileSystemAppCatalog.defaultRoots) { self.roots = roots }

    static let defaultRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
    ]

    private struct Found {
        let root: Int
        let app: CatalogApp
    }

    func read() -> CatalogReading {
        var found: [Found] = []
        var complete = true
        var noID = 0
        var capped = false
        for (index, root) in roots.enumerated() {
            walk(root, depth: 0, rootIndex: index, into: &found, complete: &complete, noID: &noID, capped: &capped)
        }
        var best: [String: Found] = [:]
        var losers = 0
        for f in found {
            if let current = best[f.app.id] {
                losers += 1
                if (f.root, f.app.path) < (current.root, current.app.path) { best[f.app.id] = f }
            } else {
                best[f.app.id] = f
            }
        }
        let apps = best.values.map(\.app).sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        HelmLog.shared.info(LaunchpadEngine.moduleID,
                            "read \(apps.count) apps, \(losers) duplicate ids, \(noID) without an id"
                            + (complete ? "" : ", some folders would not open") + (capped ? ", stopped at the ceiling" : ""))
        return CatalogReading(apps: apps, complete: complete)
    }

    private func walk(_ dir: URL, depth: Int, rootIndex: Int, into found: inout [Found],
                      complete: inout Bool, noID: inout Int, capped: inout Bool) {
        guard case .listed(let entries) = DirectoryListing.contents(of: dir) else { complete = false; return }
        for entry in entries {
            if found.count >= LaunchpadLimits.maxApps { capped = true; complete = false; return }
            let name = entry.lastPathComponent
            if entry.pathExtension == "app" {
                autoreleasepool {
                    if let app = Self.app(at: entry) { found.append(Found(root: rootIndex, app: app)) } else { noID += 1 }
                }
            } else if depth < LaunchpadLimits.maxDepth, !name.hasPrefix("."), entry.pathExtension.isEmpty,
                      Self.isPlainFolder(entry) {
                walk(entry, depth: depth + 1, rootIndex: rootIndex, into: &found,
                     complete: &complete, noID: &noID, capped: &capped)
            }
        }
    }

    private static func isPlainFolder(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    /// **The one door every bundle file is read through.** Opened without blocking and without following a link at
    /// the last component, so a pipe planted as `Info.plist` cannot hold the walk, and read only when it is a regular
    /// file no larger than the shared ceiling; nil for anything else, a missing file included.
    private static func cappedRead(_ path: String) -> Data? {
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              let data = try? handle.read(upToCount: LaunchpadLimits.maxFileBytes + 1),
              data.count <= LaunchpadLimits.maxFileBytes else { return nil }
        return data
    }

    private static func dictionary(at path: String) -> [String: Any]? {
        cappedRead(path).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
    }

    /// The bundle's `Info.plist`; nil for a missing, unparseable or oversize one.
    private static func infoPlist(at url: URL) -> [String: Any]? {
        dictionary(at: url.appendingPathComponent("Contents/Info.plist").path)
    }

    /// The bundle's `InfoPlist.strings` in the person's language, as Finder picks it; nil when it has none or none reads.
    private static func localizedInfo(at url: URL) -> [String: Any]? {
        let held = Bundle(url: url)?.localizations ?? []
        for code in Bundle.preferredLocalizations(from: held, forPreferences: nil) {
            let strings = url.appendingPathComponent("Contents/Resources/\(code).lproj/InfoPlist.strings").path
            if let found = dictionary(at: strings) { return found }
        }
        return nil
    }

    private static func bundleID(in dict: [String: Any]) -> String? {
        (dict["CFBundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : LaunchpadLimits.bounded($0) }
    }

    func bundleID(atPath path: String) -> String? {
        Self.infoPlist(at: URL(fileURLWithPath: path, isDirectory: true)).flatMap(Self.bundleID(in:))
    }

    private static func app(at url: URL) -> CatalogApp? {
        guard let dict = infoPlist(at: url), let id = bundleID(in: dict) else { return nil }
        func text(_ value: Any?) -> String? { (value as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let localized = localizedInfo(at: url)
        let name = text(localized?["CFBundleDisplayName"]) ?? text(localized?["CFBundleName"])
            ?? text(dict["CFBundleDisplayName"]) ?? text(dict["CFBundleName"])
            ?? url.deletingPathExtension().lastPathComponent
        return CatalogApp(id: id, name: LaunchpadLimits.bounded(name), path: url.path)
    }

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
        CatalogWatch(roots: roots, onChange: onChange)
    }
}

/// The folders watched for as long as this object is held.
///
/// A separate type so that `deinit` is the whole of the lifetime: dropping the token
/// stops the stream, and nothing else has to remember to.
private final class CatalogWatch: @unchecked Sendable {
    private let watcher: FolderWatcher

    init(roots: [URL], onChange: @escaping @Sendable () -> Void) {
        watcher = FolderWatcher { paths in
            if CatalogChange.concerns(paths) { onChange() }
        }
        watcher.watch(roots.map(\.path)) { started in
            if !started {
                HelmLog.shared.warn(LaunchpadEngine.moduleID, "the installed apps cannot be watched — a change shows on the next read")
            }
        }
    }

    deinit { watcher.stop() }
}

/// Opens an application through LaunchServices, as the system does for a double-click.
///
/// A test process answers `false` and calls nothing: opening is a thing the owner's Mac would do.
struct SystemAppLauncher: AppLauncherPort {
    init() {}

    func open(_ url: URL) async -> Bool {
        guard !TestProcess.isRunning else { return false }
        return await Self.openOnMain(url)
    }

    @MainActor private static func openOnMain(_ url: URL) async -> Bool {
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch {
            return false
        }
    }
}
