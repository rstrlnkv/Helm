import Foundation

/// Whether an entry named after a bundle id really belongs to the app being
/// removed — one decision for every candidate the id produced, exact and
/// globbed alike, because a check applied to some of them and not the others is
/// how the same data arrives ticked by a different route.
///
/// `GlobMatch` answers a question about text; this answers the scan's. A
/// bundle id is a prefix of its vendor's next product, so `com.acme.tool*`
/// reaches `com.acme.toolPro`'s files as readily as `com.acme.tool.helper`'s,
/// and a glob hit is never `matchedByName`, so it arrives ticked
/// (Architecture/TheGates.md § The gates).
///
/// Four rules, because each alone lets a real case through:
///
/// - **A dot, or nothing.** The id inside a longer name is the same id only
///   when the name breaks at a `.` on both sides of it: `com.acme.tool.helper`
///   but not `com.acme.toolPro`.
/// - **Not another installed app.** `com.acme.tool.staging` passes the first
///   rule and is a product somebody may be running. Anything naming a longer
///   installed id belongs to that one.
/// - **Not an app the listing cannot see.** `installedBundleIDs()` reads `.app`
///   bundles two levels down and never inside a bundle, so a vendor's nested or
///   deeper product is invisible to the rule above. LaunchServices answers for
///   it, as in `OrphanDetector`; it cannot list a set, so the ids this name
///   could be (this id extended past a dot) are put to it one at a time.
/// - **The id is this app's to begin with.** The id is read from the app's own
///   `Info.plist`, where an app may write anybody's, and the exact candidates
///   (`Containers/<id>`) match no pattern. Two installed bundles declaring one
///   id is the evidence; an honest second copy wants the same answer, since its
///   data is still in use.
///
/// Every refusal fails toward leaving files behind, which is the survivable
/// direction: an unclaimed leftover costs disk space, and a wrongly claimed one
/// costs somebody else's data.
struct LeftoverOwnership {
    private let id: String
    private let installedBundleIDs: Set<String>
    private let installedPaths: Set<String>
    private let knownToSystem: (String) -> Bool

    init(bundleID: String, installedBundleIDs: Set<String>,
         installedPaths: [String],
         knownToSystem: @escaping (String) -> Bool) {
        self.id = bundleID
        self.installedBundleIDs = installedBundleIDs
        self.installedPaths = Set(installedPaths)
        self.knownToSystem = knownToSystem
    }

    /// Whether the id names something other than the app being removed as well.
    /// Reported, because a scan that claims nothing for a shared id and one that
    /// finds nothing look the same on screen.
    var idIsContested: Bool { installedPaths.count > 1 }

    func claims(name: String) -> Bool {
        guard !id.isEmpty else { return false }
        // Nothing built from a contested id is this app's — not the exact
        // candidates, and not what the globs around them reach either.
        guard !idIsContested else { return false }
        let stem = OrphanDetector.bundleID(from: name)
        guard Self.contains(stem, token: id) else { return false }
        // A longer installed id present in the same name is the better claim on
        // it. Only longer ones can be: a shorter id cannot be more specific
        // than the one the glob was built from.
        guard !installedBundleIDs.contains(where: { other in
            other != id && other.count > id.count && Self.contains(stem, token: other)
        }) else { return false }
        // The listing's blind spot, asked of LaunchServices. Only the extensions
        // of this id are worth a lookup: that is what a longer name carries.
        return !Self.longerIDs(in: stem, extending: id).contains(where: knownToSystem)
    }

    /// Does `token` appear in `name` bounded by `.` or by the ends of the name?
    /// Every occurrence is tried: a token can appear more than once, and one
    /// bounded occurrence is enough.
    private static func contains(_ name: String, token: String) -> Bool {
        !boundedOccurrences(of: token, in: name).isEmpty
    }

    private static func boundedOccurrences(of token: String, in name: String) -> [Range<String.Index>] {
        guard !token.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var searchFrom = name.startIndex
        while let range = name.range(of: token, range: searchFrom..<name.endIndex) {
            let openedCleanly = range.lowerBound == name.startIndex
                || name[name.index(before: range.lowerBound)] == "."
            let closedCleanly = range.upperBound == name.endIndex
                || name[range.upperBound] == "."
            if openedCleanly && closedCleanly { found.append(range) }
            guard range.lowerBound < name.endIndex else { break }
            searchFrom = name.index(after: range.lowerBound)
        }
        return found
    }

    /// The bundle ids a name longer than `id` could itself be: `id` grown
    /// rightwards to each following dot, from every bounded occurrence of it.
    /// `group.com.acme.tool.staging.helper` yields `com.acme.tool.staging` and
    /// `com.acme.tool.staging.helper`. A group container's prefixes (`group.`, a
    /// team id) are nobody's bundle id, so no lookup is spent on them.
    private static func longerIDs(in stem: String, extending id: String) -> [String] {
        var out: [String] = []
        for occurrence in boundedOccurrences(of: id, in: stem)
        where occurrence.upperBound < stem.endIndex {
            // The character at `upperBound` is the `.` that bounded the match.
            var cursor = stem.index(after: occurrence.upperBound)
            while let dot = stem[cursor...].firstIndex(of: ".") {
                out.append(String(stem[occurrence.lowerBound..<dot]))
                cursor = stem.index(after: dot)
            }
            out.append(String(stem[occurrence.lowerBound...]))
        }
        return out
    }
}
