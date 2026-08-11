import Foundation

/// Parses `brew desc` output — one `name: description` line per package. Cask
/// lines may carry a display name in parentheses ("figma: (Figma) …"), which is
/// dropped; the row already shows the package name.
enum BrewDescParser {
    static func parse(_ output: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in output.split(separator: "\n") {
            guard let sep = raw.range(of: ": ") else { continue }
            let name = String(raw[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
            var desc = String(raw[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
            if desc.hasPrefix("("), let close = desc.range(of: ") ") {
                desc = String(desc[close.upperBound...])
            }
            guard !name.isEmpty, !desc.isEmpty else { continue }
            out[name] = desc
        }
        return out
    }
}
