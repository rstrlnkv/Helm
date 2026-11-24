import SwiftUI
import HelmUI
import Module_Launchpad_Engine

extension LaunchpadScreenState {
    // MARK: - The snapshot

    /// The window's first snapshot waits, at most this long, for page 0's icons, so the first picture has them (a race, not a wait).
    static let firstIconsDeadline = Duration.milliseconds(120)

    /// The first snapshot is held (the mode stays `.busy`) while page 0's icons are drawn off main, then lands as any other; later ones land at once.
    /// A newer one while it waits replaces it, and none (a nil) drops it. Closing cancels the wait.
    func update(snapshot: LaunchpadSnapshot?) {
        if gated, !loadedOnce, let snapshot {
            firstSnapshot = snapshot
            if firstLoad == nil {
                let landed = ContinuousClock.now
                firstLoad = Task { [weak self] in await self?.warmFirstPage(since: landed) }
            }
            return
        }
        firstSnapshot = nil
        land(snapshot)
    }

    private func warmFirstPage(since landed: ContinuousClock.Instant) async {
        let asks = firstSnapshot.map(firstPageAsks) ?? []
        let side = geometry.icon
        let result = await icons.warm(asks, deadline: Self.firstIconsDeadline)
        firstLoad = nil
        guard !Task.isCancelled, let snapshot = firstSnapshot else { return }
        firstSnapshot = nil
        land(snapshot)
        if result.wanted > 0 {
            onIconsWarmed?(landed.duration(to: .now), result.drawn, LaunchpadIcons.pixels(side: side, scale: icons.scale), result.timedOut)
        }
    }

    /// What page 0 draws, as the screen asks it: the page is the first of `LaunchpadPaging.pages` over the arrangement's segments (the
    /// same cut `reflow` and `publishPages` make, so a page break, a large folder's four cells and an app missing from the snapshot
    /// count as they do there); an app at the grid's icon side, a folder's apps at its mini side, a large folder's last four at a tiny one.
    private func firstPageAsks(_ snapshot: LaunchpadSnapshot) -> [(path: String, side: CGFloat)] {
        guard view == .apps, search.isEmpty else { return [] }
        let segments = layoutSegments(snapshot).filter { !$0.isEmpty }
        let page = LaunchpadPaging.pages(segments, columns: geometry.columns, rows: geometry.rows, isLarge: { $0.isLarge }).pages[0]
        return page.flatMap { entry -> [(path: String, side: CGFloat)] in
            switch entry {
            case .app(let app): return [(app.path, geometry.icon)]
            case .folder(_, _, let apps, let large):
                let cells = LaunchpadFolderMark.cells(apps, large: large), mini = large ? LaunchpadFolderMark.mini(geometry.largeMark, edge: geometry.largeEdge) : LaunchpadFolderMark.mini(geometry.icon)
                return cells.shown.map { ($0.path, mini) } + cells.overflow.map { ($0.path, LaunchpadClusterCell.tiny(mini)) }
            case .gap: return []
            }
        }
    }

    private func land(_ snapshot: LaunchpadSnapshot?) {
        self.snapshot = snapshot
        if animateNextUpdate {
            animateNextUpdate = false
            withAnimation(HelmMotion.reorder) { reflow(selectFirst: false) }
        } else {
            reflow(selectFirst: false)
        }
        askRemovable()
        keepTheCardHonest()
        if let snapshot, !loadedOnce {
            loadedOnce = true
            onLoaded?(snapshot, self)
        }
    }

    /// The arrangement as entries, cut at its page breaks: an app or a folder the snapshot does not hold is not there.
    private func layoutSegments(_ snapshot: LaunchpadSnapshot) -> [[LaunchpadEntry]] {
        var segments: [[LaunchpadEntry]] = [[]]
        for item in snapshot.layout.items {
            switch item {
            case .app(let id): if let app = snapshot.apps[id] { segments[segments.count - 1].append(.app(app)) }
            case .folder(let folder):
                let apps = folder.apps.compactMap { snapshot.apps[$0] }
                if !apps.isEmpty { segments[segments.count - 1].append(.folder(id: folder.id, name: folder.name, apps: apps, large: folder.large)) }
            case .pageBreak: segments.append([])
            }
        }
        return segments
    }

    func reflow(selectFirst: Bool) {
        guard let snapshot else {
            segments = [[]]
            top = []
            assign(\.mode, .busy)
            publishPages()
            return
        }
        let hits = snapshot.search(search)
        let wantCategories = view == .categories && hits == nil
        if let hits {
            segments = [hits.compactMap { snapshot.apps[$0] }.map(LaunchpadEntry.app)]
        } else if wantCategories {
            // Each block is a folder-shaped entry with a fixed id, so the card, its paging and its reopening by id are the folder's own.
            let blocks = LaunchpadCategories.blocks(apps: snapshot.order.compactMap { snapshot.apps[$0] }, hidden: snapshot.layout.hidden,
                                                    counts: snapshot.launchCounts, now: wallClock(),
                                                    overrides: snapshot.layout.categoryOverrides) { LaunchpadCategoryName.title(for: $0) }
            segments = [blocks.map { .folder(id: $0.id, name: LaunchpadCategoryName.title(for: $0.kind), apps: $0.apps, large: true) }]
            // The locked block comes last, with no apps: what is in it is read only for the open, unlocked card.
            segments[0].append(.folder(id: LaunchpadHiddenBlock.id, name: LpStr.hiddenBlock, apps: [], large: true))
        } else {
            segments = layoutSegments(snapshot)
        }
        segments.removeAll { $0.isEmpty }
        top = Array(segments.joined())
        assign(\.categoriesShown, wantCategories)
        assign(\.moved, snapshot.layout.categoryOverrides)
        assign(\.geometry, wantCategories ? gridGeometry.pairedColumns : gridGeometry)
        if let open = openFolder {
            if open == LaunchpadHiddenBlock.id {
                if hidden.phase == .unlocked, let at = top.firstIndex(where: { $0.id == open.uuidString }) {
                    folderTile = at
                    setFolderName(LpStr.hiddenBlock)
                    assign(\.folderApps, snapshot.hiddenApps)
                } else {
                    closeFolderQuietly()
                    assign(\.selection, nil)
                }
            } else if let at = top.firstIndex(where: { $0.id == open.uuidString }), case .folder(_, let name, let apps, _) = top[at] {
                folderTile = at
                setFolderName(name)
                assign(\.folderApps, apps)
            } else {
                closeFolderQuietly()
                assign(\.selection, nil)
            }
        }
        if let carried = lift?.entry.id {
            if let fresh = carriedEntry(carried) { rebuildPreview(carrying: fresh) } else { cancelLift() }
        }
        publishCard()
        if lift != nil, openFolder != nil { seatGap() }
        assign(\.mode, snapshot.apps.isEmpty || (hits == nil && top.isEmpty) ? .noApps : hits != nil && top.isEmpty ? .noMatch : .grid)
        publishPages()
        if selectFirst {
            assign(\.selection, hits != nil && !top.isEmpty ? 0 : nil)
            assign(\.page, 0)
        } else {
            if let selectedID { assign(\.selection, shownIDs.firstIndex(of: selectedID)) }
        }
        // An equal index over other tiles (a new search) is no assignment: the name it stands for is read again here.
        rememberSelected()
    }
}
