import Foundation

/// Filename matching for leftover patterns. Supports any number of `*`
/// wildcards, which the single-star version could not: an extension container
/// can carry both a team prefix and a suffix (`TEAMID.com.app.extension`).
enum GlobMatch {
    static func matches(_ name: String, pattern: String) -> Bool {
        let parts = pattern.components(separatedBy: "*")
        guard parts.count > 1 else { return name == pattern }

        var rest = Substring(name)
        // Leading segment must sit at the start (empty when the pattern opens
        // with a star), trailing segment at the end.
        if let first = parts.first, !first.isEmpty {
            guard rest.hasPrefix(first) else { return false }
            rest = rest.dropFirst(first.count)
        }
        if let last = parts.last, !last.isEmpty {
            guard rest.hasSuffix(last) else { return false }
            rest = rest.dropLast(last.count)
        }
        // Middle segments must appear in order.
        for segment in parts.dropFirst().dropLast() where !segment.isEmpty {
            guard let found = rest.range(of: segment) else { return false }
            rest = rest[found.upperBound...]
        }
        return true
    }
}
