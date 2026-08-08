import Foundation

/// Parses `brew search` output. Some versions group results under
/// `==> Formulae` / `==> Casks` headers; 6.x prints a flat list where nothing in
/// the text says which kind a name is. So the kind is a parameter — the caller
/// asks brew one kind at a time and knows the answer before reading a line —
/// and the headers, where they appear, still override it.
///
/// Guessing "flat list means formulae" put `brew install <name>` (no `--cask`)
/// behind every cask in the results: the CLI tool got installed instead of the
/// app, and cask descriptions never loaded because they were looked up under
/// the wrong prefix.
/// **`isCask` is required, and it used to be `kind: Bool = false`.** Two things
/// were wrong with that signature and both are the defect above wearing a
/// different hat. The name said nothing — `parse(casks, kind: true)` reads as
/// «kind is true» — and the default meant a caller who forgot to say got
/// «formula» for an answer, silently, which is precisely the guess this parser
/// exists not to make. The one place that may still decide a kind on its own is
/// a `==> Casks` header, because that is brew saying it.
public enum BrewSearchParser {
    public static func parse(_ output: String, isCask kind: Bool) -> [SearchHit] {
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
