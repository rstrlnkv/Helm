import Foundation

/// One read of the world: what is installed, what the person arranged, reconciled in memory.
/// `layout` is already reconciled; resolve ids through `apps` and skip those that are not there.
struct LaunchpadSnapshot: Sendable {
    let apps: [AppID: CatalogApp]
    /// Catalog ids in presentation order.
    let order: [AppID]
    let layout: LaunchpadLayout
    let catalogComplete: Bool
    let layoutRead: LayoutRead
    /// False when this snapshot follows an edit whose save did not land.
    var saved = true

    /// Ids matching `query` in layout order, folders looked into, hidden excluded;
    /// nil for a blank query (the caller shows the layout).
    func search(_ query: String) -> [AppID]? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        var ids: [AppID] = []
        for item in layout.items {
            switch item {
            case .app(let id): ids.append(id)
            case .folder(let f): ids.append(contentsOf: f.apps)
            }
        }
        return ids.filter { id in
            !layout.hidden.contains(id) && (apps[id]?.name.localizedStandardContains(q) ?? false)
        }
    }
}
