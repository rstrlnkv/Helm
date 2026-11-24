import Foundation

/// Where an application has to live to count as installed.
///
/// LaunchServices answers with every copy of an id it has registered, and most
/// are not installations: the disk image, the download, the Trash, and the
/// update an app stages under `~/Library/Caches`. Counted as a second declarer,
/// that staged copy would make every self-updating app an impostor.
///
/// So the test is positional, like `RemovableScope`: the folders applications
/// are installed in, at any depth, rather than a list of places to distrust.
enum InstalledLocation {
    static func isInstalled(path: String, home: String) -> Bool {
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
