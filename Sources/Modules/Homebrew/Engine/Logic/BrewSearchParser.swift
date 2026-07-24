import Foundation

/// Parses `brew search <query>` output. Newer brew groups results under
/// `==> Formulae` / `==> Casks` headers; older brew prints a flat list (treated
/// as formulae). Header/blank/"no results" lines are ignored.
public enum BrewSearchParser {
    public static func parse(_ output: String) -> [SearchHit] {
        var isCask = false
        var hits: [SearchHit] = []
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("==> Formulae") { isCask = false; continue }
            if line.hasPrefix("==> Casks") { isCask = true; continue }
            if line.hasPrefix("==>") { continue }
            if line.lowercased().contains("no formulae or casks found") { continue }
            // A search result may be a single token; take the first token defensively.
            let name = line.split(separator: " ").first.map(String.init) ?? line
            hits.append(SearchHit(name: name, isCask: isCask))
        }
        return hits
    }
}
