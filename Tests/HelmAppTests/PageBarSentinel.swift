import SwiftUI
@testable import HelmApp
@testable import HelmUI

/// What a page-bar test lets a page's closures capture: when the sentinel is gone, so are the closures.
///
/// `PageKind` names the real zone a row exercises; `pageContent(_:_:)` declares a page for that zone whose
/// closures capture the sentinel (the tabs' selection write, the action and the search submit also count in
/// `hits`).
final class PageSentinel {
    var text = "from the page"
    var selected = "one"
    var hits = 0
}

enum PageKind { case tabs, actions, search }

@MainActor
func pageContent(_ kind: PageKind, _ s: PageSentinel) -> HelmPageToolbarContent {
    switch kind {
    case .tabs:
        return HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "one", title: "One", symbol: "circle"),
                   HelmToolbarTab(id: "two", title: "Two", symbol: "square")],
            selectedTab: Binding(get: { s.selected }, set: { s.selected = $0; s.hits += 1 }))
    case .actions:
        return HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "go", title: "Go", symbol: "play") { s.hits += 1 }])
    case .search:
        return HelmPageToolbarContent(search: HelmToolbarSearch(
            prompt: "Find", text: Binding(get: { s.text }, set: { s.text = $0 }),
            onSubmit: { s.hits += 1 }))
    }
}
