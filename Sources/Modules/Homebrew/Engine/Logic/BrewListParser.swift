import Foundation

/// Parses `brew list --versions [--formula|--cask]` output. Each line is
/// `name version [version…]`; the first version is kept.
public enum BrewListParser {
    public static func parse(_ output: String, isCask: Bool) -> [BrewPackage] {
        output.split(separator: "\n").compactMap { rawLine in
            // Split on any whitespace, not just spaces: a line carrying a lone
            // tab used to become a package named "\t" with an Uninstall button
            // next to it.
            let parts = rawLine.split(whereSeparator: \.isWhitespace)
            guard let name = parts.first else { return nil }
            let version = parts.count > 1 ? String(parts[1]) : ""
            return BrewPackage(name: String(name), version: version, isCask: isCask)
        }
    }
}
