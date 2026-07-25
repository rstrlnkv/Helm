import Foundation

/// Pure semantic-version comparison for the GitHub update check, including
/// dev-channel prereleases ("0.7.0-dev.2"): a prerelease sorts BELOW its own
/// release but above every earlier version.
public enum UpdateVersion {
    /// "v1.2.3" / "1.2" → [1, 2, 3]; anything from a "-" suffix on is dropped.
    static func parse(_ s: String) -> [Int] {
        let trimmed = s.hasPrefix("v") || s.hasPrefix("V") ? String(s.dropFirst()) : s
        let core = trimmed.split(separator: "-", maxSplits: 1)[0]
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
    public static func isNewer(_ latest: String, than current: String) -> Bool {
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
