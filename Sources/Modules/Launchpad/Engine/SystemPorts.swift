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
/// Names come from `Info.plist` (display name, then bundle name), then the bundle's file name.
public struct FileSystemAppCatalog: AppCatalogPort {
    private let roots: [URL]

    public init(roots: [URL] = FileSystemAppCatalog.defaultRoots) { self.roots = roots }

    public static let defaultRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
    ]

    private struct Found {
        let root: Int
        let app: CatalogApp
    }

    public func read() -> CatalogReading {
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

    private static func app(at url: URL) -> CatalogApp? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let handle = try? FileHandle(forReadingFrom: plist) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: LaunchpadLimits.maxFileBytes + 1),
              data.count <= LaunchpadLimits.maxFileBytes,
              let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let id = dict["CFBundleIdentifier"] as? String, !id.isEmpty else { return nil }
        func text(_ key: String) -> String? { (dict[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let name = text("CFBundleDisplayName") ?? text("CFBundleName") ?? url.deletingPathExtension().lastPathComponent
        return CatalogApp(id: LaunchpadLimits.bounded(id), name: LaunchpadLimits.bounded(name), path: url.path)
    }
}
