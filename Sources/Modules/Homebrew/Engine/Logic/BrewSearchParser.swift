import Foundation

/// Parses `brew search` output. Some versions group results under
/// `==> Formulae` / `==> Casks` headers; 6.x prints a flat list where nothing in
/// the text says which kind a name is. So the kind is a parameter — the caller
/// asks brew one kind at a time and knows the answer before reading a line —
/// and the headers, where they appear, still override it.
///
/// A guessed kind puts `brew install <name>` (no `--cask`) behind a cask, and
/// its description is looked up under the wrong prefix. So **`isCask` is
/// required, with no default**: a forgetful caller must not get «formula»
/// silently. The one place that may decide a kind on its own is a `==> Casks`
/// header, because that is brew saying it.
enum BrewSearchParser {
    static func parse(_ output: String, isCask kind: Bool) -> [SearchHit] {
        var isCask = kind
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
