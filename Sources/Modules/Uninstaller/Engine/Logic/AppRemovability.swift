import Foundation
import HelmRuntime

/// Whether the Uninstaller would offer this app for removal, for a caller that is not its own page.
///
/// **The gate sits in the engine because the engine is what deletes.** `SystemApp.isSystem` is
/// otherwise the page's: a `com.apple.` app in `/Applications` is a row without a checkbox, and
/// nothing below the page would stop a batch that named it. A door another module calls cannot lean
/// on a page, so the same refusals are written here, in this order, and `removalPreview` and
/// `removeApp` run them again before anything is scanned or quit:
///
/// 0. it is not Helm itself (`ownApp`: its id, an id under it, its bundle; refused as `.notOffered`),
/// 1. the candidate names an id, 2. the id is not macOS's, 3. the path is a `.app` spelled plainly
/// (no `..`, no trailing slash), 4. its folder is, once resolved, one of the four the lister reads,
/// 5. it is there, 6. the leaf is not a link (`WorkspaceAppLister.leadsElsewhere`, the same
/// question the list asks), 7. `RemovableScope` allows it.
///
/// What the bundle's own `Info.plist` says about its id is the engine's to read (a file read, and
/// this type stays free of ports); the folders and the link test are the filesystem as it is.
enum AppRemovability {
    /// The folders `WorkspaceAppLister.installedApps()` offers for removal, one level each, in its order. This is
    /// the removal gate and is narrower on purpose than the set `installedBundleIDs()` reads (`PropertyListFile`).
    static func folders(home: String) -> [String] {
        ["/Applications", home + "/Applications", "/Applications/Setapp", home + "/Applications/Setapp"]
    }

    /// Helm itself: the running app's id, an id under it (Helm Dev, the Launchpad helper), or its own bundle.
    private static func isHelm(_ candidate: AppRemovalCandidate, _ own: (bundleID: String, path: String)) -> Bool {
        candidate.bundleID == own.bundleID || candidate.bundleID.hasPrefix(own.bundleID + ".")
            || PathCanonical.resolvingWholePath(candidate.path) == PathCanonical.resolvingWholePath(own.path)
    }

    static func verdict(_ candidate: AppRemovalCandidate, home: String,
                        ownApp: (bundleID: String, path: String)? = nil) -> AppRemovalVerdict {
        guard !candidate.bundleID.isEmpty else { return .refused(.notOffered) }
        if let own = ownApp, isHelm(candidate, own) { return .refused(.notOffered) }
        guard !SystemApp.isSystem(bundleID: candidate.bundleID) else { return .refused(.system) }
        let path = candidate.path
        guard path.hasSuffix(".app"),
              URL(fileURLWithPath: path).standardizedFileURL.path == path
        else { return .refused(.notOffered) }
        let parent = PathCanonical.resolvingWholePath((path as NSString).deletingLastPathComponent)
        guard let folder = folders(home: home)
            .map({ PathCanonical.resolvingWholePath($0) })
            .first(where: { $0 == parent })
        else { return .refused(.notOffered) }
        // `attributesOfItem` is an `lstat`: a link is "there", and the next test judges it.
        guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return .refused(.gone) }
        guard !WorkspaceAppLister.leadsElsewhere(URL(fileURLWithPath: path),
                                                 inside: URL(fileURLWithPath: folder))
        else { return .refused(.notOffered) }
        guard RemovableScope.partition([path], home: home).allowed.count == 1 else { return .refused(.notOffered) }
        return .removable
    }
}
