import Foundation

/// **Which changed paths are worth another read of the installed applications.**
///
/// A path counts only if one of its components ends in `.app` and the path stops at that
/// component or at `Contents/Info.plist` inside it: an app arriving, going or being updated, not the
/// thousands of files written inside a bundle meanwhile. A path with no `.app` component is a
/// folder of apps being made or moved and counts, unless it is a hidden entry (`.DS_Store`).
enum CatalogChange {
    static func concerns(_ paths: [String]) -> Bool { paths.contains(where: concerns) }

    static func concerns(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard let app = parts.firstIndex(where: { $0.hasSuffix(".app") }) else {
            return !(parts.last?.hasPrefix(".") ?? true)
        }
        let rest = parts[(app + 1)...]
        return rest.isEmpty || rest.elementsEqual(["Contents", "Info.plist"])
    }
}
