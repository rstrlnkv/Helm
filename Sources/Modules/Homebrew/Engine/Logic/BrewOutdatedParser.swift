import Foundation

/// Parses `brew outdated --json=v2` into `[OutdatedPackage]` across the
/// `formulae` and `casks` arrays.
///
/// **nil is "this is not an answer", and it is not the same as an empty list.**
/// Both of `Root`'s fields are optional — a cask carries no `pinned` key and a
/// brew that prints only one of the two arrays is still answering — so *any*
/// JSON object at all satisfied the decode, and a document naming neither array
/// came back as a confident «nothing is outdated»: no throw, no log, nothing to
/// notice, for as long as that brew is installed. A newer brew that re-nests
/// the arrays and a document cut off mid-write are the two ways to reach it,
/// and the page draws either as «Updates: 0» over a machine it never read.
enum BrewOutdatedParser {
    private struct Root: Decodable { let formulae: [Entry]?; let casks: [Entry]? }
    private struct Entry: Decodable {
        let name: String
        let installed_versions: [String]?
        let current_version: String?
        /// Absent on casks, which cannot be pinned.
        let pinned: Bool?
    }

    /// nil when the bytes are not a document this parser recognises: not JSON,
    /// cut off mid-write, or a JSON object naming neither array.
    static func parse(_ data: Data) -> [OutdatedPackage]? {
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              root.formulae != nil || root.casks != nil else { return nil }
        func map(_ entries: [Entry]?, isCask: Bool) -> [OutdatedPackage] {
            (entries ?? []).map {
                OutdatedPackage(name: $0.name,
                                installed: $0.installed_versions?.first ?? "",
                                latest: $0.current_version ?? "",
                                isCask: isCask,
                                pinned: $0.pinned ?? false)
            }
        }
        return map(root.formulae, isCask: false) + map(root.casks, isCask: true)
    }
}
