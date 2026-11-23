import Foundation

/// One read of the world: what is installed, what the person arranged, reconciled in memory.
/// `layout` is already reconciled; resolve ids through `apps` and skip those that are not there.
/// The pages are `layout.items` cut at each `.pageBreak` (then by what a page holds).
public struct LaunchpadSnapshot: Equatable, Sendable {
    public let apps: [AppID: CatalogApp]
    /// Catalog ids in presentation order.
    public let order: [AppID]
    public let layout: LaunchpadLayout
    let catalogComplete: Bool
    let layoutRead: LayoutRead
    /// False when this snapshot follows an edit whose save did not land.
    public internal(set) var saved = true
    /// Launches made from Launchpad per app, read afresh from the counts file; empty when there is none or it would not read.
    public internal(set) var launchCounts: [AppID: Int] = [:]

    /// The apps the person hid that are installed, in catalog order: what the Hidden block and the settings page show once unlocked.
    public var hiddenApps: [CatalogApp] { order.filter { layout.hidden.contains($0) }.compactMap { apps[$0] } }

    /// Ids matching `query` in layout order, folders looked into, hidden excluded;
    /// nil for a blank query (the caller shows the layout).
    public func search(_ query: String) -> [AppID]? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        var ids: [AppID] = []
        for item in layout.items {
            switch item {
            case .app(let id): ids.append(id)
            case .folder(let f): ids.append(contentsOf: f.apps)
            case .pageBreak: break
            }
        }
        return ids.filter { id in
            !layout.hidden.contains(id) && (apps[id]?.name.localizedStandardContains(q) ?? false)
        }
    }
}
