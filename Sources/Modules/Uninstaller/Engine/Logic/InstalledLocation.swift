import Foundation

/// Where an application has to live to count as installed.
///
/// LaunchServices is asked which bundles declare a given id, because a
/// directory listing cannot see the one inside `/Applications/Adobe Acrobat
/// DC/`. It answers with every copy it has registered, and most copies are not
/// installations: the disk image the app was dragged out of, the download
/// beside it, the copy in the trash — and the one that would do real damage, the
/// update an app stages under `~/Library/Caches` before swapping itself, which
/// carries the same bundle id by definition. Counted as a second declarer, that
/// staged copy would leave every self-updating app looking like an impostor and
/// its leftovers unclaimable.
///
/// So the test is positional, the way `RemovableScope` is positional: the
/// folders applications are installed in, at any depth, rather than a list of
/// places to distrust.
public enum InstalledLocation {
    public static func isInstalled(path: String, home: String) -> Bool {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        return folders(home: home).contains { path.hasPrefix($0 + "/") }
    }

    /// `/System/Library` in full would take in every framework's helper; only
    /// CoreServices holds applications.
    private static func folders(home: String) -> [String] {
        [home + "/Applications",
         "/Applications",
         "/System/Applications",
         "/System/Library/CoreServices"]
    }
}
