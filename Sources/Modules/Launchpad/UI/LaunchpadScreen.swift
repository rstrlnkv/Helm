import SwiftUI
import HelmRuntime
import HelmUI
import Module_Launchpad_Engine

/// What the full-screen window draws: the apps in pages, a search field, page dots, a notice, and a folder's card over
/// the page that holds it. Drawn white on the window's blur, in the dark appearance.
///
/// **Nothing here measures.** The sizes are `state.geometry`, made from the screen and the grid settings; the pages are placed by `.offset`,
/// not scrolled, the grid's and an open folder's card alike; only the shown page and its two neighbours exist as views, and the grids are fixed cells, not lazy ones.
/// The keys and the wheel do not come through the views: the panel hands them to `state` (`LaunchpadPanel`).
struct LaunchpadScreen: View {
    @ObservedObject var vm: LaunchpadViewModel
    @ObservedObject var state: LaunchpadScreenState
    @FocusState private var searchFocused: Bool
    @FocusState private var nameFocused: Bool
    @FocusState private var removalFocused: Bool
    @State private var nameSelection: TextSelection?
    @State private var armed = false
    @State private var cardShown = false
    @Environment(\.helmTraits) private var traits

    var body: some View {
        let g = state.geometry
        ZStack(alignment: .topLeading) {
            // The scrim over the blur; a click on it, and on anything else the layers above leave free, is the background's.
            Color.black.opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture { state.backgroundClicked() }
                .contextMenu { if state.editAllowed, !state.editing { Button(HelmWord.edit) { [weak state] in state?.beginEditing() } } }
            // The content settles from a little larger as the window is revealed (a scrub or a settle, `state.reveal`); the scrim stays out of the zoom.
            ZStack(alignment: .topLeading) {
                pages(g)
                states
                searchField(g)
                if g.switchFits { viewSwitch(g) }
                if state.editing, g.doneFits { doneButton(g) }
                bottom(g)
                if state.openFolder != nil {
                    folderScrim(g)
                    folderCard(g)
                }
                if let ask = state.removalAsk { removalCard(ask, g) }
                if let carried = state.lift {
                    // The carried tile keeps its own size: a large folder's block is two cells a side.
                    let size = CGSize(width: g.cellWidth * (carried.entry.isLarge ? 2 : 1), height: g.cellHeight * (carried.entry.isLarge ? 2 : 1))
                    LiftOverlay(point: state.liftPoint, cell: size) {
                        tile(carried.entry, selected: false, size: size, g, carrying: true)
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .modifier(RevealEffect(reveal: state.reveal))
        }
        .frame(width: g.size.width, height: g.size.height)
        .animation(HelmMotion.emphasis, value: state.openFolder)
        .helmRoot()
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LpStr.moduleName)
        .accessibilityAction(.escape) { state.escape() }
        .onChange(of: vm.snapshot, initial: true) { _, new in state.update(snapshot: new) }
        .onChange(of: vm.grid) { _, new in state.regrid(new) }
        .onChange(of: state.openFolder) { _, open in if open == nil { searchFocused = true } }
        .onChange(of: state.renaming) { _, on in
            if on {
                nameFocused = true
                if state.selectNameOnFocus { Task { @MainActor in nameSelection = TextSelection(range: state.nameDraft.startIndex..<state.nameDraft.endIndex) } }
            } else {
                nameFocused = false
                if state.openFolder != nil { searchFocused = true }
            }
        }
        // The field lost the keyboard some other way (a click elsewhere): what was typed is kept.
        .onChange(of: nameFocused) { _, focused in
            if focused { state.renaming = true } else if state.renaming { state.commitName() }
        }
        // False first: the field may already hold the flag (set before the panel was key), and a flag set again is no change to act on.
        .onChange(of: state.searchFocusRequest) {
            searchFocused = false
            Task { @MainActor in searchFocused = true }
        }
        .onAppear { searchFocused = true }
    }

    // MARK: - Pages

    private func pages(_ g: LaunchpadGeometry) -> some View {
        let live = max(0, state.page - 1)...min(state.pageCount - 1, state.page + 1)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(live), id: \.self) { index in
                pageView(index, g)
                    .offset(x: CGFloat(index - state.page) * g.pageWidth)
            }
        }
        .modifier(PageDragOffset(drag: state.drag))
        .frame(width: g.pageWidth, height: g.pageHeight, alignment: .topLeading)
        .padding(.top, g.gridTop)
        .allowsHitTesting(state.openFolder == nil)
    }

    /// The page's tiles, each at its own cells (`state.slots`, from `LaunchpadPlacement`): left to right from the grid's left edge,
    /// so a short last row keeps its columns, and a large folder is a block of four cells.
    private func pageView(_ index: Int, _ g: LaunchpadGeometry) -> some View {
        let entries = state.pages[index]
        let slots = state.slots.indices.contains(index) ? state.slots[index] : []
        return ZStack(alignment: .topLeading) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { at, entry in
                if slots.indices.contains(at) {
                    let frame = g.frame(of: slots[at])
                    tile(entry, selected: state.openFolder == nil && state.selection == state.flatIndex(page: index, slot: at), size: frame.size, g)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(width: g.pageWidth, height: g.pageHeight, alignment: .topLeading)
    }

    private func tile(_ entry: LaunchpadEntry, selected: Bool, size: CGSize, _ g: LaunchpadGeometry, carrying: Bool = false) -> some View {
        // The edit mode's wiggle and badges stay with the tiles in the page; the one the pointer carries is plain.
        let wearing = state.editing && !carrying
        let canEdit = state.editAllowed && !state.editing
        return Group {
            switch entry {
            case .app(let app):
                LaunchpadTile(app: app, icon: state.icons.image(for: app.path, side: g.icon), iconSize: g.icon, selected: selected,
                              glowSize: size, popped: state.launching == app.id,
                              pressed: state.pressedID == app.id || state.lift?.onto == app.id,
                              moved: state.moved[app.id], open: { [weak state] in state?.openApp(app.id, app.name) }, hide: { [weak state] in state?.onHide?(app.id) },
                              move: { [weak state] in state?.move(app.id, to: $0) }, reorder: state.moves(for: app.id),
                              files: state.fileActions(for: app), showName: g.names, isNew: isNew(app) && !state.editing, scale: g.scale,
                              editMode: wearing ? appEdit(app) : nil, beginEditing: canEdit ? { [weak state] in state?.beginEditing() } : nil)
            case .folder(let id, let name, let apps, let large):
                if state.categoriesShown, id == LaunchpadHiddenBlock.id {
                    // The locked block: a lock and a name, nothing of what it holds; a press or Return asks the system.
                    LaunchpadTile(name: LpStr.hiddenBlock, accessibleName: LpStr.hiddenLocked, iconSize: g.largeMark, selected: selected,
                                  open: { [weak state] in state?.open(folder: id) }, hide: nil, glowSize: size,
                                  pressed: state.pressedID == entry.id, oneLine: !g.names, scale: g.scale) {
                        LaunchpadHiddenMark(size: g.largeMark, edge: g.largeEdge)
                    }
                } else if state.categoriesShown {
                    // A category block: three large icons that launch and a cluster of four small ones, or four large ones when it has no more
                    // (`LaunchpadHit.categoryIcon`). Its menu has no Hide and no size: it is no folder of the person's. Each large icon has the
                    // app's own menu (Hide and Move to category), by right-click.
                    let large = apps.prefix(apps.count > 4 ? 3 : 4)
                    let mine = state.pressedID == entry.id
                    LaunchpadTile(name: name, accessibleName: LpStr.category(name), iconSize: g.largeMark, selected: selected,
                                  open: { [weak state] in state?.open(folder: id) }, hide: nil, glowSize: size,
                                  pressed: mine && state.pressedIcon == nil, oneLine: !g.names, scale: g.scale) {
                        let quadrant = LaunchpadCategoryMark.quadrant(g.largeMark, edge: g.largeEdge)
                        LaunchpadCategoryMark(large: large.map { state.icons.image(for: $0.path, side: quadrant) },
                                              cluster: apps.dropFirst(3).prefix(apps.count > 4 ? 4 : 0).map { state.icons.image(for: $0.path, side: LaunchpadClusterCell.tiny(quadrant)) },
                                              size: g.largeMark, edge: g.largeEdge,
                                              pressed: mine ? large.firstIndex { $0.id == state.pressedIcon } : nil,
                                              popped: state.popped(block: entry.id, among: large),
                                              menu: { [weak state] at in
                                                  let app = large[at]
                                                  return LaunchpadAppMenu(app: app, moved: state?.moved[app.id], hide: { [weak state] in state?.onHide?(app.id) },
                                                                          move: { [weak state] in state?.move(app.id, to: $0) }, files: state?.fileActions(for: app))
                                              })
                    }
                } else {
                    // A large folder shows the first eight apps and, past nine, four more in the ninth cell, or the first nine; the mark's icons are plain images, and a click on one is the state's (the panel takes the press).
                    let cells = LaunchpadFolderMark.cells(apps, large: large)
                    let mini = large ? LaunchpadFolderMark.mini(g.largeMark, edge: g.largeEdge) : LaunchpadFolderMark.mini(g.icon)
                    LaunchpadTile(name: name, accessibleName: LpStr.folder(name), iconSize: large ? g.largeMark : g.icon, selected: selected,
                                  open: { [weak state] in state?.open(folder: id) }, hide: nil, glowSize: size,
                                  pressed: (state.pressedID == entry.id && state.pressedIcon == nil) || state.lift?.onto == entry.id,
                                  resize: (large ? LpStr.shrinkFolder : LpStr.enlargeFolder, { [weak state] in state?.resize(id, large: !large) }),
                                  reorder: state.moves(for: entry.id), oneLine: !g.names, scale: g.scale,
                                  editMode: wearing ? LaunchpadTileEdit(seed: LaunchpadTileEdit.seed(of: entry.id)) : nil,
                                  beginEditing: canEdit ? { [weak state] in state?.beginEditing() } : nil) {
                        LaunchpadFolderMark(icons: cells.shown.map { state.icons.image(for: $0.path, side: mini) }, size: large ? g.largeMark : g.icon, edge: large ? g.largeEdge : nil,
                                            overflow: cells.overflow.map { state.icons.image(for: $0.path, side: LaunchpadClusterCell.tiny(mini)) },
                                            pressed: large ? cells.shown.firstIndex { $0.id == state.pressedIcon } : nil,
                                            popped: large ? cells.shown.firstIndex { $0.id == state.launching } : nil)
                    }
                }
            case .gap:
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// What an app's tile wears in the edit mode: the eye, and the × where the Uninstaller offers the app.
    private func appEdit(_ app: CatalogApp) -> LaunchpadTileEdit {
        LaunchpadTileEdit(seed: LaunchpadTileEdit.seed(of: app.id),
                          remove: state.badges(for: app).contains(.remove) ? { [weak state] in state?.askToRemove(app.id) } : nil,
                          hide: { [weak state] in state?.onHide?(app.id) })
    }

    /// The "new" dot: added in the last 30 days and never opened from Launchpad, by the model's counts as they are now (a launch that
    /// refreshed them takes the dot off at the next draw).
    private func isNew(_ app: CatalogApp) -> Bool {
        LaunchpadCategories.isNew(added: app.added, launches: vm.snapshot?.launchCounts[app.id] ?? 0, now: state.wallClock())
    }

    private func glowSize(_ g: LaunchpadGeometry) -> CGSize { CGSize(width: g.cellWidth, height: g.cellHeight) }

    // MARK: - States

    @ViewBuilder private var states: some View {
        switch state.mode {
        case .busy: HelmBusyState().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noApps: HelmEmptyState(message: LpStr.noApps).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noMatch: HelmEmptyState(message: LpStr.noMatch).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .grid: EmptyView()
        }
    }

    // MARK: - Search, dots, notice

    private func searchField(_ g: LaunchpadGeometry) -> some View {
        HStack(spacing: HelmSpace.s3) {
            Image(systemName: "magnifyingglass").foregroundStyle(LaunchpadMetrics.secondaryInk).accessibilityHidden(true)
            TextField(text: $state.search, prompt: Text(HelmControlName.searchApps).foregroundStyle(LaunchpadMetrics.placeholderInk)) { Text(HelmControlName.searchApps) }
                .textFieldStyle(.plain)
                .focused($searchFocused)
        }
        .padding(.horizontal, HelmSpace.s5)
        .frame(width: LaunchpadMetrics.searchWidth, height: LaunchpadMetrics.searchHeight)
        .background(Capsule().fill(LaunchpadMetrics.fieldFill))
        .frame(width: g.size.width)
        .padding(.top, g.searchTop)
        .allowsHitTesting(state.openFolder == nil)
    }

    /// "Apps" and "Categories" at the left of the search field, on its row, from the grid's left edge. The kit's segmented tabs; dimmed
    /// and off while a search is typed, since a search shows its matches flat.
    private func viewSwitch(_ g: LaunchpadGeometry) -> some View {
        let tabs = [HelmToolbarTab(id: LaunchpadViewMode.apps.rawValue, title: HelmWord.apps, symbol: "square.grid.2x2"),
                    HelmToolbarTab(id: LaunchpadViewMode.categories.rawValue, title: LpStr.categories, symbol: "rectangle.3.group")]
        return HelmHeaderTabs(tabs: tabs, selection: Binding(get: { state.view.rawValue },
                                                            set: { state.setView(LaunchpadViewMode(rawValue: $0) ?? .apps) }),
                              enabled: state.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.leading, g.sideInset)
            .padding(.top, g.searchTop - (LaunchpadMetrics.switchHeight - LaunchpadMetrics.searchHeight) / 2)
            .allowsHitTesting(state.openFolder == nil)
    }

    /// "Done" at the right of the search field, on its row, from the grid's right edge: the mirror of the switch. A window with no room for it (`doneFits`) has it above the dots (`bottom`).
    private func doneButton(_ g: LaunchpadGeometry) -> some View {
        Button(HelmWord.done) { [weak state] in state?.endEditing() }
            .frame(height: LaunchpadMetrics.switchHeight)
            .padding(.trailing, g.sideInset)
            .frame(width: g.size.width, alignment: .trailing)
            .padding(.top, g.searchTop - (LaunchpadMetrics.switchHeight - LaunchpadMetrics.searchHeight) / 2)
            .allowsHitTesting(state.openFolder == nil)
    }

    private func bottom(_ g: LaunchpadGeometry) -> some View {
        VStack(spacing: HelmSpace.s5) {
            if let notice = vm.notice { HelmBanner(LpStr.text(of: notice), fillsWidth: false) }
            if state.hidden.unavailable { HelmBanner(LpStr.hiddenUnavailable, fillsWidth: false) }
            if state.editing, !g.doneFits { Button(HelmWord.done) { [weak state] in state?.endEditing() } }
            if state.pageCount > 1 { pageDots(count: state.pageCount, current: state.page, dot: g.dotSize, hit: g.dotHit) }
        }
        .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
        .offset(y: -g.dotsBottom)
    }

    /// One dot for each page, the shown one lit; a press goes to its page, on the interface curve. The grid's and the card's.
    private func pageDots(count: Int, current: Int, dot: CGFloat, hit: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Button { withAnimation(HelmMotion.interface) { state.go(to: index) } } label: {
                    Circle().fill(Color.white.opacity(index == current ? 0.9 : LaunchpadMetrics.unlitDot))
                        .frame(width: dot, height: dot)
                        .frame(width: hit, height: hit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LpStr.pageNumber(index + 1, of: count))
                .accessibilityAddTraits(index == current ? .isSelected : [])
            }
        }
    }

    // MARK: - A folder's card

    private func folderCard(_ g: LaunchpadGeometry) -> some View {
        let entries = state.cardEntries
        let grid = LaunchpadSurface.Card(geometry: g, count: entries.count, page: state.cardPage)
        let card = grid.rect
        let from = state.folderOrigin
        let delta = CGSize(width: from.x - g.size.width / 2, height: from.y - g.size.height / 2)
        return VStack(spacing: g.cardGap) {
            Group {
                if state.categoriesShown {
                    // A category's name is the block's, not a name a person gives.
                    Text(state.folderName).multilineTextAlignment(.center).lineLimit(1)
                } else {
                    TextField(LpStr.folderNameField, text: $state.nameDraft, selection: $nameSelection)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .focused($nameFocused)
                        .accessibilityLabel(LpStr.folderNameField)
                }
            }
            .font(HelmText.sectionHeading).foregroundStyle(Color.white)
            .frame(height: LaunchpadGeometry.cardTitle)
            cardPages(grid, entries, g)
                .overlay { if entries.isEmpty { Text(LpStr.noHiddenApps).font(HelmText.rowDetail).foregroundStyle(LaunchpadMetrics.secondaryInk).multilineTextAlignment(.center) } }
            if grid.paged {
                pageDots(count: grid.pageCount, current: grid.page, dot: 8, hit: LaunchpadGeometry.cardDots)
                    .frame(height: LaunchpadGeometry.cardDots)
            }
        }
        .padding(g.cardPadding)
        .frame(width: card.width, height: card.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HelmRadius.panel, style: .continuous))
        .frame(width: g.size.width, height: g.size.height)
        .transition(.modifier(active: FolderZoom(delta: delta, scale: 0.25, shown: false),
                              identity: FolderZoom(delta: .zero, scale: 1, shown: true)))
    }

    /// The card's tiles, a page at a time: the shown page and its neighbours, each at its place in the card's own width, the
    /// card's fingers moving them all. Tiles are indexed in the folder's whole list, as the choice and the lift count them.
    private func cardPages(_ grid: LaunchpadSurface.Card, _ entries: [LaunchpadEntry], _ g: LaunchpadGeometry) -> some View {
        let live = max(0, grid.page - 1)...min(grid.pageCount - 1, grid.page + 1)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(live), id: \.self) { index in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(grid.range(ofPage: index)), id: \.self) { at in
                        let slot = at - index * grid.capacity
                        cardTile(entries[at], index: at, g)
                            .frame(width: g.cellWidth, height: g.cellHeight)
                            .offset(x: CGFloat(slot % grid.columns) * g.cellWidth, y: CGFloat(slot / grid.columns) * g.cellHeight)
                    }
                }
                .frame(width: grid.pageWidth, height: CGFloat(grid.visibleRows) * g.cellHeight, alignment: .topLeading)
                .offset(x: CGFloat(index - grid.page) * grid.pageWidth)
                .accessibilityHidden(index != grid.page)
                .allowsHitTesting(index == grid.page)
            }
        }
        .modifier(PageDragOffset(drag: state.cardDrag))
        .frame(width: grid.pageWidth, height: CGFloat(grid.visibleRows) * g.cellHeight, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder private func cardTile(_ entry: LaunchpadEntry, index: Int, _ g: LaunchpadGeometry) -> some View {
        let inHidden = state.openFolder == LaunchpadHiddenBlock.id
        if case .app(let app) = entry {
            LaunchpadTile(app: app, icon: state.icons.image(for: app.path, side: g.icon), iconSize: g.icon,
                          selected: state.selection == index, glowSize: glowSize(g),
                          popped: state.launching == app.id, pressed: state.pressedID == app.id,
                          inHidden: inHidden, moved: state.moved[app.id], open: { [weak state] in state?.openApp(app.id, app.name) },
                          hide: { [weak state] in inHidden ? state?.onUnhide?(app.id) : state?.onHide?(app.id) },
                          move: { [weak state] in state?.move(app.id, to: $0) }, reorder: state.moves(for: app.id),
                          files: state.fileActions(for: app), showName: inHidden || state.namesAsked, oneLine: !g.names, isNew: isNew(app) && !state.editing, scale: g.scale,
                          editMode: state.editing && !inHidden ? appEdit(app) : nil, beginEditing: state.editAllowed && !state.editing ? { [weak state] in state?.beginEditing() } : nil)
        } else {
            Color.clear
        }
    }

    /// The question before an app is moved to the Trash, over everything: a scrim whose click cancels, and a card with the focus on its title.
    /// Counting says it is looking for the app's files and asks nothing yet; the question comes with what was counted. The card is the folder card's:
    /// the same material, corners and white ink. Its button waits out the state's dwell (`removalDwell`) before it works, and looks it.
    private func removalCard(_ ask: LaunchpadScreenState.RemovalAsk, _ g: LaunchpadGeometry) -> some View {
        ZStack {
            Color.black.opacity(LaunchpadMetrics.scrim)
                .contentShape(Rectangle())
                .onTapGesture { state.cancelRemoval() }
            VStack(spacing: HelmSpace.s5) {
                switch ask {
                case .counting(_, let name):
                    removalTitle(name)
                    HelmBusyLabel(LpStr.lookingForFiles, busy: true)
                    Button(HelmWord.cancel) { state.cancelRemoval() }.keyboardShortcut(.cancelAction)
                case .asking(_, let name, let counted):
                    removalTitle(name)
                    let items = Plural.items(1 + counted.leftoverCount, language: AppLanguage.current.rawValue)
                    Text(counted.appBytes.map { HelmConfirm.trash(items, Bytes($0 + counted.leftoverBytes)) } ?? LpStr.moveToTrashNoSize(items))
                        .multilineTextAlignment(.center)
                    if counted.running {
                        Label(LpStr.removeRunning(name), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HelmSignal.warning(increased: traits.increasedContrast))
                            .multilineTextAlignment(.center)
                    }
                    LaunchpadRemovalButtons(confirm: counted.running ? LpStr.quitAndMoveToTrash : HelmWord.moveToTrash, armed: armed,
                                            cancel: { state.cancelRemoval() }, remove: { state.confirmRemoval() })
                }
            }
            .foregroundStyle(Color.white)
            .padding(HelmSpace.s6)
            .frame(maxWidth: LaunchpadMetrics.removalCardWidth)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HelmRadius.panel, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .opacity(cardShown ? 1 : 0)
        }
        .frame(width: g.size.width, height: g.size.height)
        .onAppear { removalFocused = true; withAnimation(HelmMotion.interface) { cardShown = true } }
        .onDisappear { cardShown = false }
        .onChange(of: ask) { removalFocused = true }
        .task(id: ask) {
            armed = false
            try? await Task.sleep(for: .seconds(LaunchpadScreenState.removalDwell))
            armed = true
        }
    }

    private func removalTitle(_ name: String) -> some View {
        Text(LpStr.removeTitle(name)).font(HelmText.sectionHeading).multilineTextAlignment(.center)
            .focusable().focusEffectDisabled().focused($removalFocused)
    }

    /// The dimming behind the card; it fades and takes no clicks on its way out.
    private func folderScrim(_ g: LaunchpadGeometry) -> some View {
        Color.black.opacity(LaunchpadMetrics.scrim)
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(Rectangle())
            .onTapGesture { state.backgroundClicked() }
            .transition(.modifier(active: FolderZoom(delta: .zero, scale: 1, shown: false),
                                  identity: FolderZoom(delta: .zero, scale: 1, shown: true)))
    }
}

/// The pages moved by the fingers. Its own observer of the drag, so the 120 Hz of a swipe re-runs this body (one `.offset`)
/// and not the screen's.
private struct PageDragOffset: ViewModifier {
    @ObservedObject var drag: LaunchpadPageDrag

    func body(content: Content) -> some View { content.offset(x: drag.offset) }
}

/// The carried tile, one step larger than its neighbours (none under Reduce Motion), where the pointer is. Its own observer of
/// the pointer, so the event rate re-runs this body (one `.offset`) and not the screen's. It takes no click.
private struct LiftOverlay<Content: View>: View {
    @ObservedObject var point: LaunchpadLiftPoint
    let cell: CGSize
    @ViewBuilder let content: Content
    @State private var grown = false

    var body: some View {
        content
            .scaleEffect(grown && !HelmMotion.reduceMotion ? LaunchpadMetrics.liftScale : 1)
            .offset(x: point.point.x + point.grab.x - cell.width / 2, y: point.point.y + point.grab.y - cell.height / 2)
            .allowsHitTesting(false)
            .onAppear { withAnimation(HelmMotion.reorder) { grown = true } }
    }
}

/// A folder's card between its tile and the middle of the window: small and at the tile when it is not `shown`. A card on
/// its way out takes no clicks, so a click during the fold falls to nothing and does not close the window.
private struct FolderZoom: ViewModifier {
    let delta: CGSize
    let scale: CGFloat
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(HelmMotion.reduceMotion ? 1 : scale)
            .offset(HelmMotion.reduceMotion ? .zero : delta)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
    }
}

/// The content's zoom from how far the window is revealed; the fade is the panel's alpha, which the icons share with the backdrop
/// (a second `.opacity(p)` here would multiply to p squared). No `.animation`: the progress is already the curve's value
/// (a settle's own clock) or the fingers'.
private struct RevealEffect: ViewModifier {
    @ObservedObject var reveal: LaunchpadReveal

    func body(content: Content) -> some View {
        let p = reveal.progress
        content
            .scaleEffect(HelmMotion.reduceMotion ? 1 : LaunchpadMetrics.zoomFrom + (1 - LaunchpadMetrics.zoomFrom) * p)
    }
}

/// The removal card's two buttons: side by side when both fit `LaunchpadMetrics.removalRoom`, one above the other when they do not (German and Russian
/// "Quit and Move to Trash"). Cancel answers Esc in both. The destructive one is disabled until `armed`.
struct LaunchpadRemovalButtons: View {
    let confirm: String
    var armed = true
    var cancel: () -> Void = {}
    var remove: () -> Void = {}

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { cancelButton; removeButton }
            VStack { removeButton; cancelButton }
        }
        .frame(maxWidth: LaunchpadMetrics.removalRoom)
    }

    private var cancelButton: some View { Button(HelmWord.cancel, action: cancel).keyboardShortcut(.cancelAction) }
    private var removeButton: some View { Button(confirm, role: .destructive, action: remove).disabled(!armed) }
}
