import Foundation

/// Parses `brew list --versions [--formula|--cask]` output. Each line is
/// `name version [version…]`; the first version is kept.
public enum BrewListParser {
    public static func parse(_ output: String, isCask: Bool) -> [BrewPackage] {
        output.split(separator: "\n").compactMap { rawLine in
            let parts = rawLine.split(separator: " ", omittingEmptySubsequences: true)
            guard let name = parts.first else { return nil }
            let version = parts.count > 1 ? String(parts[1]) : ""
            return BrewPackage(name: String(name), version: version, isCask: isCask)
        }
    }
}
