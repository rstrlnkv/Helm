import SwiftUI
import HelmRuntime
import HelmUI
import Module_Launchpad_Engine

extension LaunchpadScreenState {
    /// The edit mode may begin: a lift may (`liftAllowed`), in the app grid (not the category view), and not in the Hidden card.
    var editAllowed: Bool { liftAllowed && !categoriesShown && openFolder != LaunchpadHiddenBlock.id }

    /// The badges an app's tile wears in the edit mode: the eye on every app, the × on one the Uninstaller offers.
    /// None in the Hidden card, whose apps are neither hidden again here nor offered to the removal door.
    func badges(for app: CatalogApp) -> LaunchpadBadge.Kinds {
        if openFolder == LaunchpadHiddenBlock.id { return [] }
        return removable.contains(app.id) ? [.remove, .hide] : .hide
    }

    /// The shown tiles' badges by address: the open card's, else the page's.
    var badged: [Int: LaunchpadBadge.Kinds] {
        var out: [Int: LaunchpadBadge.Kinds] = [:]
        if openFolder != nil {
            for (at, entry) in cardEntries.enumerated() { if case .app(let app) = entry { out[at] = badges(for: app) } }
        } else if pages.indices.contains(page) {
            for (slot, entry) in pages[page].enumerated() { if case .app(let app) = entry { out[page * geometry.capacity + slot] = badges(for: app) } }
        }
        return out
    }

    /// The mode begins (a long press, or Edit in a menu): nothing while it is not allowed or already on.
    func beginEditing() {
        guard editAllowed, !editing else { return }
        assign(\.editing, true)
        HelmA11y.announce(LpStr.editModeOn)
        askRemovable()
    }

    /// Done, Esc, the background, a search typed, the category view: the mode ends and its answer about what is removable goes with it.
    func endEditing() {
        guard editing else { return }
        leaveEditing()
        HelmA11y.announce(HelmWord.done)
    }

    func leaveEditing() {
        cancelRemoval()
        assign(\.editing, false)
        assign(\.removable, [])
        removableFor = nil
        verdictTask?.cancel()
        verdictTask = nil
    }

    /// The × on an app's tile was pressed: the confirmation of its removal, which `editing` alone does not start.
    func askToRemove(_ id: AppID) {
        guard editing, removalAsk == nil, removable.contains(id), openFolder != LaunchpadHiddenBlock.id,
              let snapshot, !snapshot.layout.hidden.contains(id), let app = snapshot.apps[id], let preview = onPreview else { return }
        assign(\.removalAsk, .counting(id, name: app.name))
        let candidate = Self.candidate(app)
        askedFor = candidate
        previewTask = Task { @MainActor [weak self] in
            let counted = await preview(candidate)
            guard !Task.isCancelled, let self, case .counting(id, _)? = removalAsk else { return }
            askedAt = clock()
            assign(\.removalAsk, counted.map { .asking(id, name: app.name, $0) })
        }
    }

    /// Cancel, Esc, the scrim, and every end of the mode or the window: nothing is removed.
    func cancelRemoval() {
        previewTask?.cancel()
        previewTask = nil
        askedFor = nil
        assign(\.removalAsk, nil)
    }

    /// A card whose app the snapshot no longer holds as it was counted (gone, renamed, moved, hidden) is no question to answer: it closes.
    func keepTheCardHonest() {
        guard removalAsk != nil else { return }
        let id: AppID
        switch removalAsk { case .counting(let i, _)?, .asking(let i, _, _)?: id = i; case nil: return }
        if let app = snapshot?.apps[id], Self.candidate(app) == askedFor, snapshot?.layout.hidden.contains(id) == false { return }
        cancelRemoval()
    }

    /// The card's button: nothing in its first moments, and nothing if the snapshot no longer holds the app exactly as the card counted it
    /// (the card is closed instead); the consent to quit is given only if the card said the app was open.
    func confirmRemoval() {
        guard case .asking(let id, _, let counted)? = removalAsk, clock() - askedAt >= Self.removalDwell else { return }
        let asked = askedFor
        cancelRemoval()
        guard editing, openFolder != LaunchpadHiddenBlock.id, let snapshot, !snapshot.layout.hidden.contains(id),
              let app = snapshot.apps[id], Self.candidate(app) == asked else { return }
        onRemove?(Self.candidate(app), counted.running)
    }

    private static func candidate(_ app: CatalogApp) -> AppRemovalCandidate { AppRemovalCandidate(bundleID: app.id, path: app.path, name: app.name) }

    /// Asks the removal door about the snapshot's apps that are not macOS's own, unless it was asked about these apps at these paths already.
    func askRemovable() {
        guard editing, let snapshot, let ask = onVerdicts else { return }
        let paths = snapshot.apps.mapValues(\.path)
        guard paths != removableFor else { return }
        removableFor = paths
        verdictTask?.cancel()
        let candidates = snapshot.apps.values.filter { !$0.id.hasPrefix("com.apple.") && !snapshot.layout.hidden.contains($0.id) }.map { AppRemovalCandidate(bundleID: $0.id, path: $0.path, name: $0.name) }
        verdictTask = Task { @MainActor [weak self] in
            let verdicts = await ask(candidates)
            guard !Task.isCancelled, let self, editing, removableFor == paths else { return }
            assign(\.removable, Set(zip(candidates, verdicts).filter { $0.1 == .removable }.map(\.0.bundleID)))
        }
    }
}
