import Foundation

/// Pure semantic-version comparison for the GitHub update check, including
/// dev-channel prereleases ("0.7.0-dev.2"): a prerelease sorts BELOW its own
/// release but above every earlier version.
enum UpdateVersion {
    /// "v1.2.3" → [1, 2, 3], "1.2" → [1, 2]; what follows a "-" inside the
    /// version is dropped ("0.7.0-dev.2" → [0, 7, 0]), and a leading "-" is
    /// skipped, so "-5" and "v-2" read as [5] and [2]. A part with no digit in
    /// front reads as 0 ("nightly" → [0]); a tag with no part at all ("v", "V",
    /// "-", "") reads as [], which compares as a final 0.0.0: a published tag is
    /// never deleted, so it comes back at every check and must not stop the
    /// process.
    static func parse(_ s: String) -> [Int] {
        let trimmed = s.hasPrefix("v") || s.hasPrefix("V") ? String(s.dropFirst()) : s
        // `split` leaves out empty parts, so "" and "-" give no part at all.
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

    /// True when `latest` is a strictly higher version than `current`.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let a = parse(latest), b = parse(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        // Same numeric core: a final release beats a prerelease; two
        // prereleases compare by ordinal.
        switch (prereleaseOrdinal(latest), prereleaseOrdinal(current)) {
        case (nil, nil): return false
        case (nil, _?): return true       // 0.7.0 > 0.7.0-dev.3
        case (_?, nil): return false      // 0.7.0-dev.3 < 0.7.0
        case (let x?, let y?): return x > y
        }
    }
}
