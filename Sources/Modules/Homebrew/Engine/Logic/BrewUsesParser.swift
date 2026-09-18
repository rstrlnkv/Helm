import Foundation

/// Parses `brew uses --installed` into the names it printed.
///
/// One name per line and nothing else — the tool's warnings go to stderr, which
/// the runner drops, so there is no diagnostic here to mistake for a package.
/// Unlike the other parsers in this folder there is no shape that can be wrong,
/// which is why this answers `[String]` and not `[String]?`: an empty answer is
/// a leaf, and the refusal it must not be confused with is read from the exit
/// code by the caller, before these bytes are looked at.
enum BrewUsesParser {
    static func parse(_ output: String) -> [String] {
        output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
