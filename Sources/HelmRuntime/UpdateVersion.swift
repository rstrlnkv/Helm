import Foundation

/// Pure semantic-version comparison for the GitHub update check.
public enum UpdateVersion {
    /// "v1.2.3" / "1.2" → [1, 2, 3]; non-numeric suffixes are ignored.
    static func parse(_ s: String) -> [Int] {
        let trimmed = s.hasPrefix("v") || s.hasPrefix("V") ? String(s.dropFirst()) : s
        return trimmed.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    /// True when `latest` is a strictly higher version than `current`.
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        let a = parse(latest), b = parse(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
