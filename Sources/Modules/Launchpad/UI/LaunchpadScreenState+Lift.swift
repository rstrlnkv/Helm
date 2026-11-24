import SwiftUI
import HelmUI
import Module_Launchpad_Engine

extension LaunchpadScreenState {
    // MARK: - The lift

    /// A press may become a lift only with the grid shown: no search text, no name being typed, no launch under way, and the
    /// window shown (not yet, or no longer, is not).
    var liftAllowed: Bool {
        mode == .grid && search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !renaming && launching == nil && shown
    }

    /// A press is down on a tile, lifted or not: the panel hands this window's mouse events to the state, and keys and the wheel go nowhere.
    var pointerBusy: Bool { machine.isEngaged }

    /// The open card as the pointer meets it; nil when no folder is open.
    var card: LaunchpadSurface.Card? {
        openFolder == nil ? nil : LaunchpadSurface.Card(geometry: geometry, count: cardEntries.count, page: cardPage)
    }

    var surface: LaunchpadSurface {
        var surface = LaunchpadSurface(geometry: geometry, page: page, slots: slots, gap: gapAddress)
        surface.holdsToEdit = editAllowed && !editing
        if editing { surface.badged = badged }
        if let card {
            surface.card = card
            surface.gap = cardEntries.firstIndex(of: .gap)
        } else if case .app = lift?.entry {
            surface.folders = folderAddresses
        }
        return surface
    }


    /// True when the press is on a tile and the window takes it (no button sees it); false leaves it to the views.
    func pointerDown(_ point: CGPoint, time: TimeInterval) -> Bool {
        guard liftAllowed, removalAsk == nil, !machine.isEngaged else { return false }
        // A badge is a button: its press is the view's, and neither lifts nor clicks the tile under it.
        if editing, LaunchpadHit.badge(at: point, in: surface) != nil { return false }
        _ = machine.feed(.down, at: point, surface: surface, time: time)
        guard let address = machine.pressedAddress else { return false }
        lastPoint = point
        pressPoint = point
        assign(\.pressedID, entry(at: address)?.id)
        assign(\.pressedIcon, miniIcon(at: point, address: address)?.id)
        rearm()
        return true
    }

    func pointerMoved(_ point: CGPoint, time: TimeInterval) {
        lastPoint = point
        if machine.isLifted { liftPoint.point = point }
        apply(machine.feed(.moved, at: point, surface: surface, time: time))
        rearm()
    }

    func pointerUp(_ point: CGPoint, time: TimeInterval) {
        lastPoint = point
        apply(machine.feed(.up, at: point, surface: surface, time: time))
        if !machine.isEngaged { assign(\.pressedID, nil) }
        rearm()
    }

    /// The timer's turn, or a test's: what the pointer has waited for comes due. A left button that is no longer down ends the lift.
    func tick(at time: TimeInterval? = nil) {
        guard machine.isEngaged else { return }
        let effect = buttonDown()
            ? machine.feed(.tick, at: lastPoint, surface: surface, time: time ?? clock())
            : machine.feed(.abort, surface: surface)
        apply(effect)
        rearm()
    }

    /// Esc, or anything else that ends a lift without a drop: nothing is written.
    func cancelLift() {
        apply(machine.feed(.escape, surface: surface))
        rearm()
    }

    /// The window is going: no timer, no lift, nothing written (a drop already out still lands).
    func shutdown() {
        firstLoad?.cancel()
        firstLoad = nil
        firstSnapshot = nil
        onIconsWarmed = nil
        hidden.lock()
        if openFolder == LaunchpadHiddenBlock.id { closeFolderQuietly() }
        timer?.cancel()
        timer = nil
        scheduled = nil
        _ = machine.feed(.abort, surface: surface)
        leaveEditing()
        placing?.cancel()
        placing = nil
        lift = nil
        pressedID = nil
        preview = nil
        cardPreview = nil
        liftSource = .top
        publishCard()
        publishPages()
    }

    private func apply(_ effect: LaunchpadLift.Effect) {
        switch effect {
        case .none: break
        case .lift(let address): beginLift(at: address)
        case .moveGap(let address): moveGap(to: address)
        case .arm(let address):
            let id = address.flatMap { entry(at: $0) }.flatMap { $0 == .gap ? nil : $0.id }
            if let carried = lift { assign(\.lift, LaunchpadLiftView(entry: carried.entry, onto: id)) }
        case .turn(let step):
            withAnimation(HelmMotion.interface) {
                if openFolder == nil { go(to: page + step) } else { go(to: cardPage + step); seatGap() }
            }
        case .newPage: addPage()
        case .openFolder(let address):
            if case .folder(let id, _, _, _)? = entry(at: address) { openForLift(id) }
        case .closeFolder: closeForLift()
        case .release(let drop): finish(drop)
        case .cancel: endLift()
        case .beginEditing: beginEditing()
        case .click(let address):
            // The press was on the app it recorded; a snapshot that moved other tiles under the pointer since is no click on them.
            let (pressed, icon) = (pressedID, pressedIcon)
            assign(\.pressedID, nil)
            if let tile = entry(at: address), tile.id == pressed { click(tile, at: address, icon: icon) }
        }
    }

    /// One timer, armed for the machine's `wake` and left alone while that does not change.
    private func rearm() {
        guard let wake = [machine.wake, machine.stuckWake].compactMap({ $0 }).min() else {
            timer?.cancel()
            timer = nil
            scheduled = nil
            return
        }
        guard scheduled != wake else { return }
        timer?.cancel()
        scheduled = wake
        let delay = max(0, wake - clock())
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.scheduled = nil
            self.tick()
        }
    }

    func entry(at address: Int) -> LaunchpadEntry? {
        if openFolder != nil { return cardEntries.indices.contains(address) ? cardEntries[address] : nil }
        let (at, slot) = (address / geometry.capacity, address % geometry.capacity)
        return pages.indices.contains(at) && pages[at].indices.contains(slot) ? pages[at][slot] : nil
    }

    private func locate(_ id: String, in list: [[LaunchpadEntry]]) -> (segment: Int, index: Int)? {
        for (s, segment) in list.enumerated() {
            if let i = segment.firstIndex(where: { $0.id == id }) { return (s, i) }
        }
        return nil
    }

    private func beginLift(at address: Int) {
        // The tile is the one the press was on, as the page shows it now (a snapshot or a drop being written may have moved it).
        guard !categoriesShown, let tile = entry(at: address), tile != .gap, tile.id == pressedID else {
            _ = machine.feed(.abort, surface: surface)
            endLift()
            return
        }
        let shown = preview ?? segments
        let from: CGPoint
        if let open = openFolder, let card, let at = cardEntries.firstIndex(of: tile) {
            liftSource = .folder(open)
            var members = cardEntries
            members[at] = .gap
            cardPreview = members
            preview = withoutCarried(tile, in: shown, folder: open)
            from = card.center(ofSlot: at)
        } else if let at = locate(tile.id, in: shown), openFolder == nil {
            liftSource = .top
            let (on, item) = (address / geometry.capacity, address % geometry.capacity)
            guard slots.indices.contains(on), slots[on].indices.contains(item) else { return }
            var list = shown
            list[at.segment][at.index] = .gap
            preview = list
            from = geometry.center(of: slots[on][item])
        } else {
            return
        }
        liftPoint.grab = CGPoint(x: from.x - lastPoint.x, y: from.y - lastPoint.y)
        liftPoint.point = lastPoint
        assign(\.pressedID, nil)
        assign(\.selection, nil)
        assign(\.lift, LaunchpadLiftView(entry: tile, onto: nil))
        publishCard()
        publishPages()
    }

    /// The grid's tiles with the carried app out of the folder it was lifted from; the folder's tile keeps its identity, even
    /// with one app left (the engine dissolves it when the drop lands).
    private func withoutCarried(_ carried: LaunchpadEntry, in list: [[LaunchpadEntry]], folder: UUID) -> [[LaunchpadEntry]] {
        list.map { segment in
            segment.map { entry in
                guard case .folder(folder, let name, let apps, let large) = entry else { return entry }
                return .folder(id: folder, name: name, apps: apps.filter { $0.id != carried.id }, large: large)
            }
        }
    }

    /// The carried tile as the snapshot has it now, or nil when it is gone.
    func carriedEntry(_ id: String) -> LaunchpadEntry? {
        switch liftSource {
        case .top: return top.first { $0.id == id }
        case .folder(let folder):
            guard case .folder(_, _, let apps, _)? = top.first(where: { $0.id == folder.uuidString }) else { return nil }
            return apps.first { $0.id == id }.map(LaunchpadEntry.app)
        }
    }

    /// The gap takes the place of the tile at `address`: before it when that tile comes before the gap, after it when after,
    /// so the tile makes way toward where the gap was. An empty cell is the end of its page (of the card).
    private func moveGap(to address: Int) {
        if openFolder != nil { moveCardGap(to: address); return }
        guard var list = preview, let gap = locate(LaunchpadEntry.gap.id, in: list) else { return }
        let (at, slot) = (address / geometry.capacity, address % geometry.capacity)
        guard pages.indices.contains(at), let target = slot < pages[at].count ? pages[at][slot] : pages[at].last, target != .gap,
              let to = locate(target.id, in: list) else { return }
        let after = slot >= pages[at].count || (to.segment, to.index) > (gap.segment, gap.index)
        list[gap.segment].remove(at: gap.index)
        guard let moved = locate(target.id, in: list) else { return }
        list[moved.segment].insert(.gap, at: moved.index + (after ? 1 : 0))
        preview = list.filter { !$0.isEmpty }
        withAnimation(HelmMotion.reorder) { publishPages() }
    }

    private func moveCardGap(to slot: Int) {
        guard var list = cardPreview, let gap = list.firstIndex(of: .gap), let target = slot < list.count ? list[slot] : list.last,
              target != .gap, let to = list.firstIndex(of: target) else { return }
        let after = slot >= list.count || to > gap
        list.remove(at: gap)
        guard let moved = list.firstIndex(of: target) else { return }
        list.insert(.gap, at: moved + (after ? 1 : 0))
        cardPreview = list
        withAnimation(HelmMotion.reorder) { publishCard() }
    }

    /// The pointer stayed on a folder: its card opens with the gap at its end, and the lift goes on in it.
    private func openForLift(_ id: UUID) {
        guard let carried = lift?.entry else { return }
        open(folder: id)
        guard openFolder == id else { return }
        assign(\.lift, LaunchpadLiftView(entry: carried, onto: nil))
        cardPreview = folderApps.map(LaunchpadEntry.app) + [.gap]
        machine.resetDwell()
        publishCard()
        goCard(to: .max)
    }

    /// The pointer stayed outside the card: it closes, and the lift goes on over the grid. A tile lifted from the folder has
    /// no gap there yet: it takes one right after the folder's tile.
    private func closeForLift() {
        guard let open = openFolder else { return }
        closeFolderQuietly()
        if case .folder = liftSource, var list = preview, locate(LaunchpadEntry.gap.id, in: list) == nil,
           let at = locate(open.uuidString, in: list) {
            list[at.segment].insert(.gap, at: at.index + 1)
            preview = list
        }
        machine.resetDwell()
        withAnimation(HelmMotion.reorder) { publishPages() }
    }

    /// The card's entries: the folder's apps, or the lift's preview of them.
    func publishCard() {
        assign(\.cardEntries, openFolder == nil ? [] : cardPreview ?? folderApps.map(LaunchpadEntry.app))
        assign(\.cardPage, card?.page ?? 0)
    }

    /// The card's page turned under a lift: the gap takes the nearest place on the page now shown, so the carried tile has
    /// a place where it arrived and a release lands on the page the person sees.
    func seatGap() {
        guard let list = cardPreview, let gap = list.firstIndex(of: .gap) else { return }
        let range = LaunchpadSurface.Card(geometry: geometry, count: list.count, page: cardPage).range(ofPage: cardPage)
        guard !range.isEmpty, !range.contains(gap) else { return }
        moveCardGap(to: gap < range.lowerBound ? range.lowerBound : range.upperBound - 1)
    }

    /// The edge of the last page, held: a page of its own at the end, with the gap alone on it.
    private func addPage() {
        guard openFolder == nil, var list = preview, list.last != [.gap], let gap = locate(LaunchpadEntry.gap.id, in: list) else { return }
        list[gap.segment].remove(at: gap.index)
        preview = list.filter { !$0.isEmpty } + [[.gap]]
        withAnimation(HelmMotion.interface) {
            publishPages()
            go(to: pages.count - 1)
        }
    }

    /// A new snapshot while a tile is carried: the gap stays by its neighbour, the carried tile is the snapshot's own.
    func rebuildPreview(carrying fresh: LaunchpadEntry) {
        machine.resetDwell()
        assign(\.lift, LaunchpadLiftView(entry: fresh, onto: nil))
        if case .folder(let source) = liftSource {
            var list = withoutCarried(fresh, in: segments, folder: source)
            if openFolder == nil, let at = locate(source.uuidString, in: list) { list[at.segment].insert(.gap, at: at.index + 1) }
            preview = list.filter { !$0.isEmpty }
            cardPreview = openFolder == source ? folderApps.map { $0.id == fresh.id ? .gap : .app($0) } : nil
            return
        }
        var before: String?, after: String?
        if let old = preview, let gap = locate(LaunchpadEntry.gap.id, in: old) {
            let segment = old[gap.segment]
            before = gap.index > 0 ? segment[gap.index - 1].id : nil
            after = gap.index + 1 < segment.count ? segment[gap.index + 1].id : nil
        }
        var list = segments
        if let own = locate(fresh.id, in: list) { list[own.segment][own.index] = .gap }
        if let anchor = before ?? after, locate(anchor, in: list) != nil, let gap = locate(LaunchpadEntry.gap.id, in: list) {
            list[gap.segment].remove(at: gap.index)
            if let moved = locate(anchor, in: list) { list[moved.segment].insert(.gap, at: moved.index + (before != nil ? 1 : 0)) }
        }
        preview = list.filter { !$0.isEmpty }
        if openFolder != nil { cardPreview = folderApps.map(LaunchpadEntry.app) + [.gap] }
    }

    /// Nothing carried any more and nothing written: the page goes back to the snapshot's.
    private func endLift() {
        assign(\.lift, nil)
        assign(\.pressedID, nil)
        guard placing == nil else { return }
        preview = nil
        cardPreview = nil
        liftSource = .top
        publishCard()
        withAnimation(HelmMotion.reorder) { publishPages() }
    }

    /// The pointer let go: one edit by anchors, or nothing when the drop changes nothing. The page shows the drop at once
    /// and takes the engine's answer when it comes. Inside the open card it is a drop into the folder; anywhere else the card
    /// closes first and it is a drop on the grid.
    private func finish(_ drop: LaunchpadLift.Drop) {
        guard let carried = lift?.entry, snapshot != nil else { endLift(); return }
        if let open = openFolder, let card {
            var inCard = card.rect.contains(lastPoint)
            if case .edge = LaunchpadHit.at(lastPoint, in: surface) { inCard = true }
            if inCard { finishInCard(carried, folder: open); return }
            closeForLift()
        }
        guard let snapshot, let list = preview, let gap = locate(LaunchpadEntry.gap.id, in: list) else { endLift(); return }
        var destination: LaunchpadDropDestination?
        var shown = list
        var name = ""
        switch drop {
        case .onto(let address):
            shown[gap.segment].remove(at: gap.index)
            if let target = entry(at: address), target != .gap {
                destination = .onto(target.id)
                name = LaunchpadCategoryName.folderName(target: snapshot.apps[target.id]?.category, dropped: snapshot.apps[carried.id]?.category)
                // A folder only reorders: it stays on the page, beside the target as the edit puts it, until the engine answers.
                if case .folder = carried, let before = locate(target.id, in: list), let at = locate(target.id, in: shown) {
                    shown[at.segment].insert(carried, at: at.index + ((before.segment, before.index) > (gap.segment, gap.index) ? 1 : 0))
                }
            }
        case .gap:
            let segment = list[gap.segment]
            if segment.count == 1 {
                destination = gap.segment == list.count - 1 ? .newPage : nil
            } else {
                destination = gap.index > 0 ? .beside(segment[gap.index - 1].id, after: true) : .beside(segment[1].id, after: false)
            }
            shown[gap.segment][gap.index] = carried
        }
        assign(\.lift, nil)
        assign(\.pressedID, nil)
        guard let destination, let edit = snapshot.layout.edit(dropping: carried.id, source: liftSource, destination: destination, folderName: name) else {
            endLift()
            return
        }
        preview = shown.filter { !$0.isEmpty }
        withAnimation(HelmMotion.reorder) { publishPages() }
        place(edit)
    }

    /// A release over the card: the carried app lands where the gap is among the folder's apps.
    private func finishInCard(_ carried: LaunchpadEntry, folder: UUID) {
        guard let snapshot, var list = cardPreview, let gap = list.firstIndex(of: .gap) else { endLift(); return }
        let anchor: (String, after: Bool)? = gap > 0 ? (list[gap - 1].id, true) : list.count > 1 ? (list[1].id, false) : nil
        assign(\.lift, nil)
        assign(\.pressedID, nil)
        guard let edit = snapshot.layout.edit(dropping: carried.id, source: liftSource,
                                              destination: .intoFolder(folder, relativeTo: anchor?.0, after: anchor?.after ?? true), folderName: "") else {
            endLift()
            return
        }
        list[gap] = carried
        cardPreview = list
        publishCard()
        if case .top = liftSource, var grid = preview, let at = locate(LaunchpadEntry.gap.id, in: grid) {
            grid[at.segment].remove(at: at.index)
            preview = grid.filter { !$0.isEmpty }
            withAnimation(HelmMotion.reorder) { publishPages() }
        }
        place(edit)
    }

    /// Writes the edit; what the engine answers replaces the preview. A folder just made opens with its name field in hand.
    /// `then` runs last, with the answer in place.
    func place(_ edit: LaunchpadEdit, then: (() -> Void)? = nil) {
        placing = Task { @MainActor [weak self] in
            let landed = await self?.onPlace?(edit)
            guard !Task.isCancelled, let self else { return }
            self.placing = nil
            self.preview = nil
            if self.lift == nil {
                self.cardPreview = nil
                self.liftSource = .top
            }
            if let landed { self.update(snapshot: landed) } else { self.reflow(selectFirst: false) }
            if case .makeFolder(_, let target, _) = edit {
                for case .folder(let id, _, let apps, _) in self.top where apps.contains(where: { $0.id == target }) {
                    self.open(folder: id)
                    self.beginRenaming(selectAll: true)
                }
            }
            then?()
        }
    }

    /// The pages as they are drawn: the snapshot's, or the lift's preview, cut by what a page holds; the numbers the
    /// pointer's hit test reads come with them.
    func publishPages() {
        // The gap is as big as the tile carried: a block lands where the gap shows only if the gap takes the room the block will.
        let carriedLarge = lift?.entry.isLarge == true
        let (chunks, placed) = LaunchpadPaging.pages(preview ?? segments, columns: geometry.columns, rows: geometry.rows,
                                                     isLarge: { $0.isLarge || ($0 == .gap && carriedLarge) })
        assign(\.pages, chunks)
        assign(\.slots, placed)
        pageStarts = chunks.indices.map { chunks[..<$0].reduce(0) { $0 + $1.count } }
        var broken: Set<Int> = [], run = 0
        for segment in segments.dropLast() { run += segment.count; broken.insert(run) }
        keyOrder = LaunchpadKeyMove(ids: top.map(\.id), folders: Set(top.filter { if case .folder = $0 { true } else { false } }.map(\.id)),
                                    starts: pageStarts, breaks: broken)
        gapAddress = chunks.enumerated().lazy.compactMap { at, list in
            list.firstIndex(of: .gap).map { at * self.geometry.capacity + $0 }
        }.first
        folderAddresses = Set(chunks.enumerated().flatMap { at, list in
            list.indices.filter { if case .folder = list[$0] { true } else { false } }.map { at * geometry.capacity + $0 }
        })
        assign(\.page, LaunchpadPaging.clamped(page, count: chunks.count))
    }
}
