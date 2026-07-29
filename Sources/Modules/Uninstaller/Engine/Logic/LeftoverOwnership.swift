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
/// Three rules, because each alone lets a real case through:
///
/// - **A dot, or nothing.** A bundle id is a dotted path, so the id inside a
///   longer name is the same id only when the name breaks at a `.` on both
///   sides of it. That is the whole difference between `com.acme.tool.helper`
///   and `com.acme.toolPro`.
/// - **Not another installed app.** `com.acme.tool.staging` is `com.acme.tool`
///   followed by a dot, so the first rule waves it through — and it is a
///   product somebody has installed and may be running. Anything naming an
///   installed id other than this one belongs to that one.
/// - **Not an app the listing cannot see.** The rule above is answered from
///   `installedBundleIDs()`, which is `contentsOfDirectory` over four folders
///   matching `*.app` at the top level: `/Applications/Adobe Acrobat DC/Adobe
///   Acrobat.app` is not in it, nor is any helper nested inside another bundle.
///   So the vendor's *other* product is invisible to the rule written to
///   protect it, and its container, caches, scripts and LaunchAgent are claimed
///   as this app's leftovers — pre-ticked, because a glob hit is never
///   `matchedByName`. `OrphanDetector` was given `isKnownToSystem` for exactly
///   this gap, its comment recording that nested apps "were being offered for
///   deletion while their apps were installed and running"; the same witness
///   answers here. A set cannot be enumerated out of LaunchServices, so the
///   question is asked the other way round: the ids this name *could* be —
///   this id extended past a dot — are put to it one at a time.
/// - **The id is this app's to begin with.** The three rules above compare a
///   name against the id and take the id itself on trust; it is read from the
///   app's own `Info.plist`, where an app may write anybody's. That is why the
///   exact candidates need this type at all — `Containers/<id>` and the rest
///   match no pattern and went through no check, so an app declaring a
///   neighbour's id was handed the neighbour's container, ticked. Two installed
///   bundles declaring one id is the evidence, and the honest case (a Setapp
///   build beside a direct download) wants the same answer: the data belongs to
///   something that is staying.
///
/// Every refusal fails toward leaving files behind, which is the survivable
/// direction: an unclaimed leftover costs disk space, and a wrongly claimed one
/// costs somebody else's data.
public struct LeftoverOwnership {
    private let id: String
    private let installedBundleIDs: Set<String>
    private let installedPaths: Set<String>
    private let knownToSystem: (String) -> Bool

    public init(bundleID: String, installedBundleIDs: Set<String>,
                installedPaths: [String],
                knownToSystem: @escaping (String) -> Bool) {
        self.id = bundleID
        self.installedBundleIDs = installedBundleIDs
        self.installedPaths = Set(installedPaths)
        self.knownToSystem = knownToSystem
    }

    /// Suffixes macOS appends to per-app files; they are not part of the id.
    /// The same list `OrphanDetector` strips, for the same reason.
    private static let fileSuffixes = [".plist", ".savedState", ".binarycookies"]

    /// Whether the id names something other than the app being removed as well.
    /// Reported rather than inferred from an empty result: a scan that claims
    /// nothing because the id is shared and a scan that finds nothing are the
    /// same screen and different facts.
    public var idIsContested: Bool { installedPaths.count > 1 }

    public func claims(name: String) -> Bool {
        guard !id.isEmpty else { return false }
        // Nothing built from a contested id is this app's — not the exact
        // candidates, and not what the globs around them reach either.
        guard !idIsContested else { return false }
        let stem = Self.fileSuffixes.first(where: name.hasSuffix)
            .map { String(name.dropLast($0.count)) } ?? name
        guard Self.contains(stem, token: id) else { return false }
        // A longer installed id present in the same name is the better claim on
        // it. Only longer ones can be: a shorter id cannot be more specific
        // than the one the glob was built from.
        guard !installedBundleIDs.contains(where: { other in
            other != id && other.count > id.count && Self.contains(stem, token: other)
        }) else { return false }
        // The listing's blind spot, asked of LaunchServices instead. Only the
        // extensions of this id are worth a lookup: an app installed one folder
        // down still has an id of its own, and that id is what a name longer
        // than this one carries.
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
    /// `com.acme.tool.staging.helper` — the two things somebody could have
    /// installed. The prefixes a group container carries (`group.`, a team id)
    /// are nobody's bundle id, so no lookup is spent on them.
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
