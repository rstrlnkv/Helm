import Foundation

/// Parses `brew uses --installed` into the names it printed.
///
/// One name per line; brew's warnings go to stderr, which the runner drops.
/// No shape can be wrong, so this answers `[String]`, not `[String]?`: the
/// refusal is read from the exit code by the caller first.
enum BrewUsesParser {
    static func parse(_ output: String) -> [String] {
        output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
