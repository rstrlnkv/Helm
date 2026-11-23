import SwiftUI
import Module_Launchpad_Engine

// MARK: - The menus

extension LaunchpadScreenState {
    /// Whether a menu may open: the window shown, no removal question up, no tile held by the pointer.
    private var menuAllowed: Bool { shown && removalAsk == nil && !machine.isEngaged }

    /// The menu under `point` (the window's coordinates, from the top left), or nil where there is none and the press goes on to the view under it
    /// (the search field's and the folder name field's own text menus). A tile's menu, a category block's large icon's (its app's), a folder's, and
    /// else the background's (Edit), which is off while a card is open and under the search field.
    func menu(at point: CGPoint) -> LaunchpadMenu? {
        guard menuAllowed else { return nil }
        switch LaunchpadHit.at(point, in: surface) {
        case .tile(let address, _):
            guard let entry = entry(at: address) else { return nil }
            return menu(of: entry, at: point, address: address)
        case .gap, .none, .edge, .away:
            let field = CGRect(x: (geometry.size.width - LaunchpadMetrics.searchWidth) / 2, y: geometry.searchTop,
                               width: LaunchpadMetrics.searchWidth, height: LaunchpadMetrics.searchHeight)
            return openFolder == nil && editAllowed && !editing && !field.contains(point) ? .background : nil
        }
    }

    /// The menu of the tile `id` and where to pop it (its middle), for VoiceOver; nil for a tile with no menu.
    func menu(forTile id: String) -> (menu: LaunchpadMenu, anchor: CGPoint)? {
        guard menuAllowed else { return nil }
        let found: (entry: LaunchpadEntry, address: Int, anchor: CGPoint)
        if let card {
            guard let at = cardEntries.firstIndex(where: { $0.id == id }), card.range(ofPage: card.page).contains(at) else { return nil }
            found = (cardEntries[at], at, card.center(ofSlot: at))
        } else {
            guard pages.indices.contains(page), slots.indices.contains(page), let at = pages[page].firstIndex(where: { $0.id == id }),
                  slots[page].indices.contains(at) else { return nil }
            let frame = geometry.frame(of: slots[page][at]).offsetBy(dx: 0, dy: geometry.gridTop)
            found = (pages[page][at], page * geometry.capacity + at, CGPoint(x: frame.midX, y: frame.midY))
        }
        if case .folder = found.entry, categoriesShown { return nil }
        return menu(of: found.entry, at: found.anchor, address: found.address).map { ($0, found.anchor) }
    }

    private func menu(of entry: LaunchpadEntry, at point: CGPoint, address: Int) -> LaunchpadMenu? {
        let canEdit = editAllowed && !editing
        switch entry {
        case .app(let app):
            return .app(app, moved: moved[app.id], hasFiles: filed(app.id) != nil, inHidden: openFolder == LaunchpadHiddenBlock.id, canEdit: canEdit,
                        removable: editing && badges(for: app).contains(.remove))
        case .folder(let id, _, _, let large):
            guard categoriesShown else { return .folder(id, large: large, canEdit: canEdit) }
            guard id != LaunchpadHiddenBlock.id, let app = miniIcon(at: point, address: address) else { return nil }
            return .app(app, moved: moved[app.id], hasFiles: filed(app.id) != nil)
        case .gap:
            return nil
        }
    }

    /// A menu row was chosen: what it names is looked up again, as the snapshot holds it now.
    func perform(_ action: LaunchpadMenuAction) {
        switch action {
        case .hide(let id): onHide?(id)
        case .show(let id): onUnhide?(id)
        case .move(let id, let target):
            // The row of the category the app is in is checked, and choosing it does nothing.
            if let target, let app = snapshot?.apps[id], target == LaunchpadMenu.effective(moved: moved[id], raw: app.category) { return }
            move(id, to: target)
        case .reveal(let id): if let now = filed(id) { onRevealApp?(now.app.path) }
        case .copyPath(let id): if let now = filed(id) { onCopyPath?(now.app.path, now.hidden) }
        case .resize(let id, let large): resize(id, large: large)
        case .beginEditing: beginEditing()
        case .askToRemove(let id): askToRemove(id)
        }
    }

    /// VoiceOver's "show menu" on a tile: the menu is popped outside the accessibility callback, from the id alone.
    func requestMenu(forTile id: String) {
        Task { @MainActor [weak self] in
            guard let self, let found = menu(forTile: id) else { return }
            onPopMenu?(found.menu, found.anchor)
        }
    }
}
