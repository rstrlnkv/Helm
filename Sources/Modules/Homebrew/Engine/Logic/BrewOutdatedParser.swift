import Foundation

/// Parses `brew outdated --json=v2` into `[OutdatedPackage]` across the
/// `formulae` and `casks` arrays.
public enum BrewOutdatedParser {
    private struct Root: Decodable { let formulae: [Entry]?; let casks: [Entry]? }
    private struct Entry: Decodable {
        let name: String
        let installed_versions: [String]?
        let current_version: String?
        /// Absent on casks, which cannot be pinned.
        let pinned: Bool?
    }

    public static func parse(_ data: Data) -> [OutdatedPackage] {
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return [] }
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
