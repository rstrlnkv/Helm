import Foundation

/// Pure semantic-version comparison for the GitHub update check, including
/// dev-channel prereleases ("0.7.0-dev.2"): a prerelease sorts BELOW its own
/// release but above every earlier version. The build-tag form
/// ("v0.11.1.BETA.1620", versioning.md rule 6) names a build: on an equal
/// X.Y.Z it is read against the running build number.
enum UpdateVersion {
    /// "v1.2.3" / "1.2" → [1, 2, 3]; anything from a "-" suffix on is dropped.
    static func parse(_ s: String) -> [Int] {
        let trimmed = s.hasPrefix("v") || s.hasPrefix("V") ? String(s.dropFirst()) : s
        // "", "v" and "-" split into nothing: no core, which no version is newer than.
        let core = trimmed.split(separator: "-", maxSplits: 1).first ?? ""
        return core.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    /// The prerelease ordinal: nil for a final release, otherwise the trailing
    /// number ("0.7.0-dev.2" → 2, "0.7.0-dev" → 0).
    static func prereleaseOrdinal(_ s: String) -> Int? {
        let parts = s.split(separator: "-", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let digits = parts[1].split(whereSeparator: { !$0.isNumber }).last
        return digits.flatMap { Int($0) } ?? 0
    }

    /// "v0.11.1.BETA.1620" → ([0, 11, 1], 1620); nil for every other spelling,
    /// a signed number ("-5", "+5") included: `Int` reads both.
    /// The tag form of versioning.md rule 6: the number after DEV / BETA is a
    /// build number, not a fifth version part, which `parse` would make it.
    static func buildTag(_ s: String) -> (core: [Int], build: Int)? {
        let parts = (s.hasPrefix("v") || s.hasPrefix("V") ? String(s.dropFirst()) : s)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 5, ["DEV", "BETA"].contains(parts[3]), let build = unsigned(parts[4])
        else { return nil }
        let core = parts[0..<3].compactMap(unsigned)
        return core.count == 3 ? (core, build) : nil
    }

    private static func unsigned(_ s: Substring) -> Int? {
        s.allSatisfy(\.isNumber) ? Int(s) : nil
    }

    /// -1, 0, 1 for two numeric cores, a missing part reading as 0.
    private static func compare(_ a: [Int], _ b: [Int]) -> Int {
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    /// True when `latest` is a strictly higher version than `current`.
    ///
    /// `currentBuild` is the running build number (CFBundleVersion, which
    /// `Scripts/package-app.sh` writes as `git rev-list --count HEAD`). A build
    /// tag (`vX.Y.Z.BETA.<build>`) names a build, so on an equal X.Y.Z with the
    /// build known, `tag.build > currentBuild` decides, whatever suffix the
    /// running version has. With the build unknown (nil), a running old-form
    /// prerelease (`-dev.N`) is offered the tag and a running bare X.Y.Z is
    /// not, so a tag that may be the running build is not offered on every check.
    static func isNewer(_ latest: String, than current: String, currentBuild: Int? = nil) -> Bool {
        if let tag = buildTag(latest) {
            if let other = buildTag(current) {
                let c = compare(tag.core, other.core)
                return c != 0 ? c > 0 : tag.build > other.build
            }
            let c = compare(tag.core, parse(current))
            if c != 0 { return c > 0 }
            if let build = currentBuild { return tag.build > build }
            return prereleaseOrdinal(current) != nil
        }
        if let other = buildTag(current) {
            // The list picker's branch: an old-form tag never beats a build tag of the same core.
            return compare(parse(latest), other.core) > 0
        }
        let a = parse(latest), b = parse(current)
        let c = compare(a, b)
        if c != 0 { return c > 0 }
        // Same numeric core: a final release beats a prerelease; two
        // prereleases compare by ordinal.
        switch (prereleaseOrdinal(latest), prereleaseOrdinal(current)) {
        case (nil, nil): return false
        case (nil, _?): return true       // 0.7.0 > 0.7.0-dev.3
        case (_?, nil): return false      // 0.7.0-dev.3 < 0.7.0
        case (let x?, let y?): return x > y
        }
    }

    /// A total order for the list picker: `isNewer`, and where it says neither
    /// is newer, a build tag above an old-form tag (bare or `-dev.N`) of the same
    /// core, so the pick does not depend on the order of the list.
    static func ranksAbove(_ a: String, _ b: String) -> Bool {
        if isNewer(a, than: b) { return true }
        if isNewer(b, than: a) { return false }
        return buildTag(a) != nil && buildTag(b) == nil
    }
}
