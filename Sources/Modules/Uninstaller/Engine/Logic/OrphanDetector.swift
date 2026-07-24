import Foundation

/// Decides whether a `~/Library` entry is left over from an app that is no longer
/// installed. Deliberately conservative: only entries whose name looks like a
/// bundle id (`com.acme.tool`) are considered, so plain folders like "Google" or
/// "Firefox" — which can belong to an installed app, a plug-in, or the system —
/// are never flagged. Apple's own domains are always skipped.
public enum OrphanDetector {
    /// Domains that belong to macOS itself or to Helm; never orphan candidates.
    static let skippedPrefixes = ["com.apple.", "com.helm."]

    /// A name qualifies if it has at least two dots (reverse-DNS shape) and no spaces.
    public static func looksLikeBundleID(_ name: String) -> Bool {
        guard !name.contains(" ") else { return false }
        let base = stripKnownSuffix(name)
        return base.split(separator: ".").count >= 3
    }

    /// Strips the file suffixes macOS appends to per-app support files, so
    /// `com.acme.tool.plist` and `com.acme.tool.savedState` map to the bundle id.
    public static func bundleID(from name: String) -> String {
        stripKnownSuffix(name)
    }

    private static func stripKnownSuffix(_ name: String) -> String {
        for suffix in [".plist", ".savedState", ".binarycookies"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// True when `name` is a bundle-id-shaped entry whose app isn't installed.
    public static func isOrphan(name: String, installedBundleIDs: Set<String>) -> Bool {
        guard looksLikeBundleID(name) else { return false }
        let id = bundleID(from: name)
        guard !skippedPrefixes.contains(where: { id.hasPrefix($0) }) else { return false }
        // ByHost prefs carry a UUID tail (com.acme.tool.<UUID>); match on prefix too.
        if installedBundleIDs.contains(id) { return false }
        return !installedBundleIDs.contains { id.hasPrefix($0 + ".") }
    }
}
