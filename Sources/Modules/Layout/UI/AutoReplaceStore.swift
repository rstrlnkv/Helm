import Foundation
import HelmRuntime
import Module_Layout_Engine

/// Where the abbreviation table lives.
///
/// JSON in one value rather than a pair of parallel string arrays: the two
/// halves of an entry belong together, and two arrays that can differ in length
/// is a defect waiting for someone to delete a row from one of them.
enum AutoReplaceStore {
    static let key = "autoReplace"

    static func load(_ store: NamespacedStore) -> [AutoReplace.Entry] {
        guard let data = store.data(key),
              let entries = try? JSONDecoder().decode([AutoReplace.Entry].self, from: data)
        else { return [] }
        return entries
    }

    static func save(_ entries: [AutoReplace.Entry], to store: NamespacedStore) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        store.set(data, for: key)
    }
}
