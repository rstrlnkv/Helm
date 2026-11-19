import Foundation

extension LaunchpadLayout {

    /// The stored layout set against what is installed now: apps that are new appear at
    /// the end in catalog order, apps that are gone fall out — but only when the read was
    /// `complete`, since an unreadable folder looks the same as an uninstalled app.
    /// `catalog` is in presentation order (by name, then id). Idempotent. Never saved by itself.
    func reconciled(catalog: [AppID], complete: Bool) -> LaunchpadLayout {
        var out = self
        if complete {
            let known = Set(catalog)
            out.hidden = hidden.filter(known.contains)
            out.items = items.compactMap {
                switch $0 {
                case .app(let id): return known.contains(id) ? $0 : nil
                case .folder(var f): f.apps.removeAll { !known.contains($0) }; return .folder(f)
                case .pageBreak: return $0
                }
            }
        }
        out = out.normalized()
        var placed = out.hidden
        for item in out.items {
            switch item {
            case .app(let id): placed.insert(id)
            case .folder(let f): placed.formUnion(f.apps)
            case .pageBreak: break
            }
        }
        for id in catalog.prefix(LaunchpadLimits.maxApps) where placed.insert(id).inserted {
            out.items.append(.app(id))
        }
        return out.normalized()
    }
}
