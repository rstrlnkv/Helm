import Foundation

/// Whether an entry a glob matched really belongs to the app being removed.
///
/// `GlobMatch` answers a question about text; this answers the question the
/// scan actually has. Every id-derived candidate is `"<id>*"` or `"*<id>*"`,
/// and a bundle id is a prefix of its own vendor's next product — so
/// `com.acme.tool*` reaches `com.acme.toolPro`'s cache, container, group
/// container and LaunchAgent as readily as it reaches `com.acme.tool.helper`'s.
/// `scanOrphansSync` puts every entry it finds past `installedBundleIDs()`
/// before offering it; `scanSync` put its glob matches past nothing, and a glob
/// hit is never `matchedByName`, so `UninstallPlan.defaultSelection` arrives
/// with it **already ticked** — the hazard ARCHITECTURE.md § Removal scope is
/// about.
///
/// Two rules, because either alone lets a real case through:
///
/// - **A dot, or nothing.** A bundle id is a dotted path, so the id inside a
///   longer name is the same id only when the name breaks at a `.` on both
///   sides of it. That is the whole difference between `com.acme.tool.helper`
///   and `com.acme.toolPro`.
/// - **Not another installed app.** `com.acme.tool.staging` is `com.acme.tool`
///   followed by a dot, so the first rule waves it through — and it is a
///   product somebody has installed and may be running. Anything naming an
///   installed id other than this one belongs to that one.
///
/// Both refusals fail toward leaving files behind, which is the survivable
/// direction: an unclaimed leftover costs disk space, and a wrongly claimed one
/// costs somebody else's data.
public enum LeftoverOwnership {
    /// Suffixes macOS appends to per-app files; they are not part of the id.
    /// The same list `OrphanDetector` strips, for the same reason.
    private static let fileSuffixes = [".plist", ".savedState", ".binarycookies"]

    public static func claims(name: String, bundleID id: String,
                              installedBundleIDs: Set<String>) -> Bool {
        guard !id.isEmpty else { return false }
        let stem = fileSuffixes.first(where: name.hasSuffix).map { String(name.dropLast($0.count)) } ?? name
        guard contains(stem, token: id) else { return false }
        // A longer installed id present in the same name is the better claim on
        // it. Only longer ones can be: a shorter id cannot be more specific
        // than the one the glob was built from.
        return !installedBundleIDs.contains { other in
            other != id && other.count > id.count && contains(stem, token: other)
        }
    }

    /// Does `token` appear in `name` bounded by `.` or by the ends of the name?
    /// Every occurrence is tried: a token can appear more than once, and one
    /// bounded occurrence is enough.
    private static func contains(_ name: String, token: String) -> Bool {
        guard !token.isEmpty else { return false }
        var searchFrom = name.startIndex
        while let range = name.range(of: token, range: searchFrom..<name.endIndex) {
            let openedCleanly = range.lowerBound == name.startIndex
                || name[name.index(before: range.lowerBound)] == "."
            let closedCleanly = range.upperBound == name.endIndex
                || name[range.upperBound] == "."
            if openedCleanly && closedCleanly { return true }
            guard range.lowerBound < name.endIndex else { break }
            searchFrom = name.index(after: range.lowerBound)
        }
        return false
    }
}
