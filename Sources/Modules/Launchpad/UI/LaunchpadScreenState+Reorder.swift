import SwiftUI
import HelmUI
import Module_Launchpad_Engine

extension LaunchpadScreenState {
    // MARK: - The folder's name

    /// The name the card shows is the snapshot's, unless a person is typing in the field.
    func setFolderName(_ name: String) {
        assign(\.folderName, name)
        if !renaming { assign(\.nameDraft, name) }
    }

    /// The field takes the keyboard, its text selected when `selectAll`.
    func beginRenaming(selectAll: Bool) {
        guard openFolder != nil else { return }
        selectNameOnFocus = selectAll
        assign(\.renaming, true)
    }

    /// Return, or the card closing: a changed, non-blank draft is the folder's name; a blank one is the old name again.
    func commitName() {
        guard !categoriesShown else { return }
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        assign(\.renaming, false)
        guard let id = openFolder, !name.isEmpty else { assign(\.nameDraft, folderName); return }
        guard name != folderName else { assign(\.nameDraft, name); return }
        assign(\.nameDraft, name)
        assign(\.folderName, name)
        onRename?(id, name)
    }

    /// A key while the field has the keyboard (key codes: Return 36 and 76, Esc 53): true when it was the state's, false when it
    /// goes on to the field, so the caret, the arrows and the typing are the field's.
    func handleNameKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 36, 76: commitName()
        case 53: revertName()
        default: return false
        }
        return true
    }

    /// Esc in the field: what was typed goes, the folder stays open.
    func revertName() {
        assign(\.nameDraft, folderName)
        assign(\.renaming, false)
    }

    // MARK: - Reordering by key and by VoiceOver

    /// A reorder needs an arrangement to write and nobody else writing one: the grid in the apps view (a search, the category view and
    /// its cards, the Hidden card, a name being typed and a launch under way have none), no pointer carrying a tile, no write in flight
    /// (a key during a write is dropped, not queued).
    var reorderAllowed: Bool { liftAllowed && !categoriesShown && !pointerBusy && placing == nil }

    /// Option (combine: Option+Shift) and an arrow, on the choice. True when the key was the state's; a key it is not goes on to the field.
    func reorderKey(dx: Int, dy: Int, combine: Bool) -> Bool {
        guard reorderAllowed, let selection, shownIDs.indices.contains(selection) else { return false }
        reorder(tile: shownIDs[selection], combine ? (openFolder == nil ? .combine(dx: dx, dy: dy) : .takeOut) : .move(dx: dx, dy: dy))
        return true
    }

    private struct ReorderPlan {
        let source: LaunchpadDropSource
        let destination: LaunchpadDropDestination
        var name = ""
    }

    /// What the tile's reorder is as a drop, or nil when it has none: the one place a chord and a VoiceOver action are turned into one.
    private func reorderPlan(tile id: String, _ kind: LaunchpadKeyMove.Kind) -> ReorderPlan? {
        if let folder = openFolder {
            guard let from = folderApps.firstIndex(where: { $0.id == id }) else { return nil }
            switch kind {
            case .takeOut:
                return ReorderPlan(source: .folder(folder), destination: .beside(folder.uuidString, after: true))
            case .move(let dx, let dy):
                guard let card, let to = LaunchpadPaging.moved(from, dx: dx, dy: dy, columns: card.columns, count: folderApps.count),
                      let destination = LaunchpadKeyMove.inFolder(folder, ids: folderApps.map(\.id), from: from, to: to) else { return nil }
                return ReorderPlan(source: .folder(folder), destination: destination)
            case .combine, .page: return nil
            }
        }
        guard let from = keyOrder.ids.firstIndex(of: id) else { return nil }
        switch kind {
        case .move(let dx, let dy):
            guard let to = arrowTarget(from: from, dx: dx, dy: dy), let destination = keyOrder.destination(from: from, to: to) else { return nil }
            return ReorderPlan(source: .top, destination: destination)
        case .page(let step):
            guard let to = keyOrder.pageTarget(from: from, step: step), let destination = keyOrder.destination(from: from, to: to) else { return nil }
            return ReorderPlan(source: .top, destination: destination)
        case .combine(let dx, let dy):
            guard let to = arrowTarget(from: from, dx: dx, dy: dy), let destination = keyOrder.combine(from: from, to: to) else { return nil }
            return ReorderPlan(source: .top, destination: destination,
                               name: LaunchpadCategoryName.folderName(target: snapshot?.apps[keyOrder.ids[to]]?.category, dropped: snapshot?.apps[id]?.category))
        case .takeOut: return nil
        }
    }

    /// The one way a tile's place is changed without the pointer: the same edit the matching drop makes, by anchors, through
    /// `LaunchpadLayout.edit` and `place`. Keyed by the tile, not by the choice, so a VoiceOver action works on the tile it was read on.
    /// `readAs` is what a VoiceOver action was read on (the destination, and whether it was a folder); a plan that differs by the run is refused.
    func reorder(tile id: String, _ kind: LaunchpadKeyMove.Kind, readAs: (destination: LaunchpadDropDestination, intoFolder: Bool)? = nil) {
        guard reorderAllowed, let snapshot, let name = shownName(of: id) else { return }
        let folder = openFolder.flatMap { shownName(of: $0.uuidString) } ?? ""
        guard let plan = reorderPlan(tile: id, kind),
              readAs.map({ $0.destination == plan.destination && $0.intoFolder == intoFolder(plan.destination) }) ?? true,
              let edit = snapshot.layout.edit(dropping: id, source: plan.source, destination: plan.destination, folderName: plan.name) else {
            HelmA11y.announce(LpStr.announceCannotMove(name))
            return
        }
        let other: String
        if case .onto(let target) = plan.destination { other = shownName(of: target) ?? "" } else { other = "" }
        animateNextUpdate = true
        if kind == .takeOut { closeFolder() }
        place(edit) { [weak self] in self?.reordered(id, kind, name: name, other: other, folder: folder) }
    }

    /// The answer is in: the choice and the page follow the tile, and VoiceOver is told where it is.
    private func reordered(_ id: String, _ kind: LaunchpadKeyMove.Kind, name: String, other: String, folder: String) {
        if case .combine = kind {
            if openFolder != nil {
                // The card is open over the folder's tile: the choice comes back to it on closing, so the page is the tile's now.
                if let folderTile { withAnimation(HelmMotion.reorder) { assign(\.page, LaunchpadPaging.page(of: folderTile, starts: pageStarts)) } }
                HelmA11y.announce(LpStr.announceFolderMade(name, other))
                return
            }
            follow(id)
            HelmA11y.announce(LpStr.announceAddedToFolder(name, other))
            return
        }
        if openFolder != nil {
            guard let selection, let card else { return }
            withAnimation(HelmMotion.reorder) { goCard(to: card.page(ofIndex: selection)) }
            HelmA11y.announce(LpStr.announceMoved(name, place: selection + 1, of: folderApps.count, page: card.page(ofIndex: selection) + 1, of: card.pageCount))
            return
        }
        follow(id)
        guard let at = keyOrder.ids.firstIndex(of: id) else { return }
        let pageNumber = LaunchpadPaging.page(of: at, starts: pageStarts) + 1
        HelmA11y.announce(kind == .takeOut ? LpStr.announceTakenOut(name, folder, place: at + 1, page: pageNumber)
                          : LpStr.announceMoved(name, place: at + 1, of: keyOrder.ids.count, page: pageNumber, of: pages.count))
    }

    /// The choice goes to the tile (or the folder it went into) and the page to the choice's.
    private func follow(_ id: String) {
        let at = top.firstIndex { $0.id == id } ?? top.firstIndex { if case .folder(_, _, let apps, _) = $0 { apps.contains { $0.id == id } } else { false } }
        guard let at else { return }
        withAnimation(HelmMotion.reorder) {
            assign(\.selection, at)
            assign(\.page, LaunchpadPaging.page(of: at, starts: pageStarts))
        }
    }

    /// Whether the drop is onto a folder (an add) and not onto an app (a new folder).
    private func intoFolder(_ destination: LaunchpadDropDestination) -> Bool {
        if case .onto(let target) = destination { keyOrder.folders.contains(target) } else { false }
    }

    /// The name VoiceOver is told for a tile of the grid or of the open card; nil for a tile gone (an id is a bundle id or a UUID, never spoken).
    private func shownName(of id: String) -> String? {
        if let app = folderApps.first(where: { $0.id == id }) { return app.name }
        switch top.first(where: { $0.id == id }) {
        case .app(let app)?: return app.name
        case .folder(_, let name, _, _)?: return name
        default: return nil
        }
    }

    /// What VoiceOver may do with a tile's place, each action only where the move exists; nil where no reorder is allowed.
    func moves(for id: String) -> LaunchpadTileMoves? {
        guard reorderAllowed else { return nil }
        func action(_ kind: LaunchpadKeyMove.Kind, intoFolder wanted: Bool? = nil) -> (() -> Void)? {
            guard let plan = reorderPlan(tile: id, kind) else { return nil }
            let read = (destination: plan.destination, intoFolder: intoFolder(plan.destination))
            if let wanted {
                // Only an add can be refused for what the folder holds (a full one), so only it is checked for its edit: a render's cost stays one per neighbour.
                guard read.intoFolder == wanted, !wanted || snapshot?.layout.edit(dropping: id, source: plan.source, destination: plan.destination, folderName: plan.name) != nil else { return nil }
            }
            return { [weak self] in self?.reorder(tile: id, kind, readAs: read) }
        }
        func combine(_ dx: Int, folder: Bool) -> (() -> Void)? { action(.combine(dx: dx, dy: 0), intoFolder: folder) }
        return LaunchpadTileMoves(earlier: action(.move(dx: -1, dy: 0)), later: action(.move(dx: 1, dy: 0)),
                                  previousPage: action(.page(-1)), nextPage: action(.page(1)),
                                  folderWithPrevious: combine(-1, folder: false), folderWithNext: combine(1, folder: false),
                                  addToPreviousFolder: combine(-1, folder: true), addToNextFolder: combine(1, folder: true),
                                  takeOut: action(.takeOut))
    }
}
