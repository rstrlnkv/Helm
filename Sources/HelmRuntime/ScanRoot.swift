import Foundation

/// Where a scan that nobody is watching may start.
///
/// **A fourth gate, and a different question from the other three.**
/// `RemovableScope` asks what belongs to an application, `UserFileScope` what
/// belongs to the user and may be deleted, `WatchScope` where an Autopilot rule
/// may reach. This one asks where an unattended *read* may begin — and it cannot
/// be `UserFileScope.isRemovable`, which refuses the user's home outright. The
/// home is the commonest duplicate-scan root there is, so that gate would refuse
/// the normal case.
///
/// It exists because the root is stored rather than asked for.
/// `module.duplicates.folder` is a plain unsealed string in `com.helm.app` —
/// verified live, holding the home directory. Until background scans it only
/// ever changed through an open panel with the person present; now it decides
/// how far a reader reaches with nobody there, and any process running as this
/// user can rewrite that plist.
public enum ScanRoot {

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// True for the user's home and anything inside it that exists and is a
    /// directory.
    ///
    /// Existence is checked because a root that is not there produces an empty
    /// walk, and an empty walk reported as a finding is «проверено, чисто» about
    /// a folder nobody looked in.
    public static func isAllowed(_ rawPath: String) -> Bool {
        // Absolute first, before any resolution: `URL(fileURLWithPath:)` resolves
        // a relative path against the process's working directory and hands back
        // something absolute, so canonicalizing first would answer the question
        // this guard is asking. `UserFileScope` records the same trap.
        let standardized = (rawPath as NSString).standardizingPath
        guard standardized.hasPrefix("/"), standardized != "/" else { return false }
        let path = PathCanonical.resolvingAncestors(standardized)
        guard path.hasPrefix("/"), path != "/" else { return false }

        // Folded, because the boot volume is case-insensitive while
        // `standardizingPath` resolves `..` and `~` and never case.
        let lowered = path.lowercased()
        let loweredHome = PathCanonical.resolvingAncestors(home).lowercased()
        guard lowered == loweredHome || lowered.hasPrefix(loweredHome + "/") else {
            return false
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }
        return true
    }
}
