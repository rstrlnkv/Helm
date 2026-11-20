import SwiftUI
import HelmUI
import Module_Launchpad_Engine

/// What the full-screen window draws: the apps in pages, a search field, page dots, a notice, and a folder's card over
/// the page that holds it. Drawn white on the window's blur, in the dark appearance.
///
/// **Nothing here measures.** The sizes are `state.geometry`, made from the screen and the grid settings; the pages are placed by `.offset`,
/// not scrolled; only the shown page and its two neighbours exist as views, and the grids are fixed cells, not lazy ones.
/// The keys and the wheel do not come through the views: the panel hands them to `state` (`LaunchpadPanel`).
struct LaunchpadScreen: View {
    @ObservedObject var vm: LaunchpadViewModel
    @ObservedObject var state: LaunchpadScreenState
    @FocusState private var searchFocused: Bool
    @FocusState private var nameFocused: Bool
    @State private var nameSelection: TextSelection?

    var body: some View {
        let g = state.geometry
        ZStack(alignment: .topLeading) {
            // The scrim over the blur; a click on it, and on anything else the layers above leave free, is the background's.
            Color.black.opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture { state.backgroundClicked() }
            // The content settles from a little larger as the window fades up; the scrim stays out of the zoom.
            ZStack(alignment: .topLeading) {
                pages(g)
                states
                searchField(g)
                bottom(g)
                if state.openFolder != nil {
                    folderScrim(g)
                    folderCard(g)
                }
                if let carried = state.lift {
                    LiftOverlay(point: state.liftPoint, cell: CGSize(width: g.cellWidth, height: g.cellHeight)) {
                        tile(carried.entry, selected: false, width: g.cellWidth, g)
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .scaleEffect(state.shown || HelmMotion.reduceMotion ? 1 : LaunchpadMetrics.zoomFrom)
            .opacity(state.shown ? 1 : 0)
            .animation(HelmMotion.windowZoom, value: state.shown)
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
        .onAppear {
            searchFocused = true
            state.setShown(true)
        }
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

    /// The page's tiles, each at its own slot: left to right from the grid's left edge, so a short last row keeps its columns.
    private func pageView(_ index: Int, _ g: LaunchpadGeometry) -> some View {
        let entries = state.pages[index]
        return ZStack(alignment: .topLeading) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { at, entry in
                let origin = g.origin(ofSlot: at)
                tile(entry, selected: state.openFolder == nil && state.selection == state.flatIndex(page: index, slot: at), width: g.cellWidth, g)
                    .offset(x: origin.x, y: origin.y)
            }
        }
        .frame(width: g.pageWidth, height: g.pageHeight, alignment: .topLeading)
    }

    private func tile(_ entry: LaunchpadEntry, selected: Bool, width: CGFloat, _ g: LaunchpadGeometry) -> some View {
        Group {
            switch entry {
            case .app(let app):
                LaunchpadTile(app: app, icon: state.icons.icon(for: app.path), iconSize: g.icon, selected: selected,
                              glowSize: glowSize(g), popped: state.launching == app.id,
                              pressed: state.pressedID == app.id || state.lift?.onto == app.id,
                              open: { state.onLaunch?(app.id, app.name) }, hide: { state.onHide?(app.id) })
            case .folder(let id, let name, let apps):
                LaunchpadTile(name: name, accessibleName: LpStr.folder(name), iconSize: g.icon, selected: selected,
                              open: { state.open(folder: id) }, hide: nil, glowSize: glowSize(g),
                              pressed: state.pressedID == entry.id || state.lift?.onto == entry.id) {
                    LaunchpadFolderMark(icons: apps.prefix(4).map { state.icons.icon(for: $0.path) }, size: g.icon)
                }
            case .gap:
                Color.clear
            }
        }
        .frame(width: width, height: g.cellHeight)
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
            Image(systemName: "magnifyingglass").foregroundStyle(Color.white.opacity(0.7)).accessibilityHidden(true)
            TextField(HelmControlName.searchApps, text: $state.search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
        }
        .padding(.horizontal, HelmSpace.s5)
        .frame(width: LaunchpadMetrics.searchWidth, height: LaunchpadMetrics.searchHeight)
        .background(Capsule().fill(Color.white.opacity(0.14)))
        .frame(width: g.size.width)
        .padding(.top, g.searchTop)
        .allowsHitTesting(state.openFolder == nil)
    }

    private func bottom(_ g: LaunchpadGeometry) -> some View {
        VStack(spacing: HelmSpace.s5) {
            if let notice = vm.notice { HelmBanner(LpStr.text(of: notice), fillsWidth: false) }
            if state.pageCount > 1 {
                HStack(spacing: 0) {
                    ForEach(0..<state.pageCount, id: \.self) { index in
                        Button { withAnimation(HelmMotion.interface) { state.go(to: index) } } label: {
                            Circle().fill(Color.white.opacity(index == state.page ? 0.9 : 0.35))
                                .frame(width: 8, height: 8)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LpStr.pageNumber(index + 1, of: state.pageCount))
                        .accessibilityAddTraits(index == state.page ? .isSelected : [])
                    }
                }
            }
        }
        .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
        .offset(y: -g.dotsBottom)
    }

    // MARK: - A folder's card

    private func folderCard(_ g: LaunchpadGeometry) -> some View {
        let entries = state.cardEntries
        let grid = LaunchpadSurface.Card(geometry: g, count: entries.count)
        let (columns, rows, card) = (grid.columns, grid.rows, grid.rect)
        let from = state.folderOrigin
        let delta = CGSize(width: from.x - g.size.width / 2, height: from.y - g.size.height / 2)
        return VStack(spacing: LaunchpadGeometry.cardGap) {
            TextField(LpStr.folderNameField, text: $state.nameDraft, selection: $nameSelection)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(HelmText.sectionHeading).foregroundStyle(Color.white)
                .lineLimit(1)
                .focused($nameFocused)
                .accessibilityLabel(LpStr.folderNameField)
                .frame(height: LaunchpadGeometry.cardTitle)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(Array((row * columns)..<min(entries.count, (row + 1) * columns)), id: \.self) { index in
                                cardTile(entries[index], index: index, g)
                                    .frame(width: g.cellWidth, height: g.cellHeight)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: CGFloat(columns) * g.cellWidth, height: CGFloat(grid.visibleRows) * g.cellHeight)
        }
        .padding(LaunchpadGeometry.cardPadding)
        .frame(width: card.width, height: card.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HelmRadius.panel, style: .continuous))
        .frame(width: g.size.width, height: g.size.height)
        .transition(.modifier(active: FolderZoom(delta: delta, scale: 0.25, shown: false),
                              identity: FolderZoom(delta: .zero, scale: 1, shown: true)))
    }

    @ViewBuilder private func cardTile(_ entry: LaunchpadEntry, index: Int, _ g: LaunchpadGeometry) -> some View {
        if case .app(let app) = entry {
            LaunchpadTile(app: app, icon: state.icons.icon(for: app.path), iconSize: g.icon,
                          selected: state.selection == index, glowSize: glowSize(g),
                          popped: state.launching == app.id, pressed: state.pressedID == app.id,
                          open: { state.onLaunch?(app.id, app.name) }, hide: { state.onHide?(app.id) })
        } else {
            Color.clear
        }
    }

    /// The dimming behind the card; it fades and takes no clicks on its way out.
    private func folderScrim(_ g: LaunchpadGeometry) -> some View {
        Color.black.opacity(0.35)
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
