import Foundation

/// A scan or search root, as the diagnostics log may carry it.
///
/// `Redact.path` answers for the home directory and its `/System/Volumes/Data`
/// twin, and for nothing else — which is right for a path inside the app's own
/// work and wrong for a root, because a root is chosen by the person using it:
/// `/Volumes/Anna's Work Backup` names an employer, `/Users/anna` names an
/// account. Both then sat in the file whose purpose is being attached to a bug
/// report.
///
/// What survives is the shape, because that is what triage reads — an external
/// volume, another account and a system location are three different stories —
/// and the chosen name becomes the same stable tag `Redact` gives a VPN or an
/// app.
///
/// It lives beside `Redact` because two modules log a root of their own: Disk's
/// scan root and Duplicates' search root each carried a copy of this file,
/// identical line for line, under a comment saying it belonged here.
public enum LogRoot {

    /// Directories macOS named itself. A root that is one of these carries
    /// nobody's word and goes in as it stands.
    private static let macOSOwned: Set<String> = ["/", "/System/Volumes/Data"]

    public static func label(_ root: String, home: String = NSHomeDirectory()) -> String {
        let shown = Redact.path(root, home: home)
        if shown.hasPrefix("~") { return shown }
        if macOSOwned.contains(root) { return root }
        let parts = root.split(separator: "/", omittingEmptySubsequences: true)
        // A single component under the root is a mount point or a system
        // folder — /Volumes, /Applications, /Library. The name a person chose
        // is always the one below it.
        guard parts.count > 1, let first = parts.first else { return root }
        return "/" + first + "/" + Redact.tag(root, prefix: "root")
    }
}
