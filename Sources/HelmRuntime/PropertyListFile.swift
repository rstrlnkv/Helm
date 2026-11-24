import Foundation

/// **The one door a property list from outside is read through, and the one definition of "installed".**
///
/// A bundle hands Helm its `Info.plist`, and the owner of a folder can plant anything under that name: a pipe
/// that never ends, a link to somewhere else, a file of any size. So the file is opened without blocking and
/// without following a link at the last component, and read only when it is a regular file no larger than
/// `byteCeiling`; the answer is nil for anything else, a missing file included, with no reason told apart.
public enum PropertyListFile {
    /// The shared ceiling for a property list read from outside: a larger file is unreadable.
    public static let byteCeiling = 2 * 1024 * 1024

    /// The top-level dictionary of the property list at `path`; nil when it is missing, a link at the last
    /// component, not a regular file, over `byteCeiling` or not a property list holding a dictionary.
    ///
    /// With `followingLink` a link at the last component is followed and its target is bounded the same way
    /// (never blocking, regular file only, same ceiling): for a caller whose files are legitimately links,
    /// such as a LaunchAgent a dotfile manager keeps in the person's folder. A bundle's own files are not.
    public static func dictionary(atPath path: String, followingLink: Bool = false) -> [String: Any]? {
        let fd = open(path, O_RDONLY | O_NONBLOCK | (followingLink ? 0 : O_NOFOLLOW))
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              let data = try? handle.read(upToCount: byteCeiling + 1),
              data.count <= byteCeiling else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// A bundle's `Contents/Info.plist`, read as `dictionary(atPath:)` does.
    public static func infoPlist(ofBundleAt bundle: URL) -> [String: Any]? {
        dictionary(atPath: bundle.appendingPathComponent("Contents/Info.plist").path)
    }

    /// Where applications are installed, in order: `/Applications`, `/Applications/Utilities`, the person's
    /// `Applications`, and macOS's own. `/Applications/Utilities` is a root of its own, so an app two levels
    /// below it counts.
    public static func installedRoots(home: String) -> [String] {
        ["/Applications", "/Applications/Utilities", home + "/Applications", "/System/Applications"]
    }

    /// Directory levels walked below a root; an `.app` directly in a root is level 0.
    public static let installedDepth = 2

    /// **Every bundle id that is still installed.** An `.app` at level 0, 1 or 2 under a root counts (vendors nest:
    /// `/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app`); a folder that is not an `.app` is walked,
    /// a folder link too, since the depth is bounded; an `.app` is never walked into, so a helper inside another
    /// bundle is not listed. An empty id is not inserted.
    ///
    /// This set only ever says "this id is still installed, so its files are not orphans": a wider set offers
    /// fewer things for removal, which is the safe side. It is not the set the Uninstaller offers for removal.
    public static func installedBundleIDs(home: String) -> Set<String> {
        installedBundleIDs(roots: installedRoots(home: home))
    }

    /// The same walk over roots of the caller's choosing, so a test can point it at a scratch tree.
    public static func installedBundleIDs(roots: [String]) -> Set<String> {
        var ids: Set<String> = []
        for root in roots { collect(URL(fileURLWithPath: root), depth: 0, into: &ids) }
        return ids
    }

    private static func collect(_ dir: URL, depth: Int, into ids: inout Set<String>) {
        // `atPath:` follows a link at `dir` itself; the `at:` form answers "not a directory" for one.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names {
            let item = dir.appendingPathComponent(name)
            // One `Info.plist` per application: a bulk read of file contents, so the pool goes inside the iteration.
            autoreleasepool {
                if item.pathExtension == "app" {
                    if let id = infoPlist(ofBundleAt: item)?["CFBundleIdentifier"] as? String, !id.isEmpty {
                        ids.insert(id)
                    }
                } else if depth < installedDepth, isFolder(item) {
                    collect(item, depth: depth + 1, into: &ids)
                }
            }
        }
    }

    /// `fileExists` follows a link, which `URL.resourceValues` does not: a linked folder is a folder here.
    private static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
