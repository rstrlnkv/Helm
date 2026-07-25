import Foundation

/// The order modules appear in the menu-bar panel. Stored as a list of ids so
/// it survives modules being added or removed between versions.
public enum ModuleOrder {
    /// Saved ids first (in their saved order), then anything the user has never
    /// arranged, in registry order. Ids that no longer exist are dropped.
    public static func apply(saved: [String], to registry: [String]) -> [String] {
        let known = Set(registry)
        let arranged = saved.filter(known.contains)
        let remaining = registry.filter { !arranged.contains($0) }
        return arranged + remaining
    }

    /// Reorders for a drag in a list: `destination` is the index the moved
    /// items land *before*, the same contract SwiftUI's `onMove` uses.
    public static func move(_ ids: [String], from source: IndexSet, to destination: Int) -> [String] {
        let moved = source.sorted().map { ids[$0] }
        var out = ids
        // Remove from the back so earlier indices stay valid.
        for index in source.sorted(by: >) { out.remove(at: index) }
        let landing = destination - source.filter { $0 < destination }.count
        out.insert(contentsOf: moved, at: min(max(landing, 0), out.count))
        return out
    }
}
