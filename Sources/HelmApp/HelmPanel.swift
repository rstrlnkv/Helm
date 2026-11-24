import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import HelmAppStrings

/// Internal because `HelmPanel` (PanelWindow.swift) hosts it.
struct HelmPanelContent: View {
    @ObservedObject var host: ModuleHost
    /// The panel has its own hosting view, so the settings window's rebuild
    /// does not reach it. Labels are computed properties, so a language change
    /// alters no view's inputs; only a new identity rebuilds them.
    @State private var languageRevision = 0
    @State private var utilitiesExpanded = false
    /// The panel is being arranged rather than read.
    ///
    /// Settable at construction only so a probe can render the mode offscreen.
    @State private var editing: Bool

    init(host: ModuleHost, editing: Bool = false) {
        self.host = host
        _editing = State(initialValue: editing)
    }
    @State private var layout = PanelLayout(tabs: [])
    /// Which tab is being looked at. Not stored, and reset on every opening:
    /// the panel is opened for a glance, from its first tab.
    @State private var activeTab = 0
    /// The card has played its entrance. Set false for the one frame the
    /// entrance animates from, then true again.
    ///
    /// True to begin with: a path that shows the window without `toggle` posts
    /// no entrance, and starting at false would draw the panel at zero opacity.
    /// The worst this way round is a missing animation.
    @State private var revealed = true
    /// The drawer is choosing its rows rather than showing them.
    @State private var choosingUtilities = false
    @State private var showEditButton = AppSettings.shows(.edit)
    @State private var showSettingsButton = AppSettings.shows(.settings)
    @State private var showQuitButton = AppSettings.shows(.quit)
    /// The strip the panel is drawn in, top to bottom of the screen. The card
    /// may not be taller than it, and the grid is what gives way.
    @State private var stripHeight: CGFloat = 0
    /// The grid's natural height, so the scroll view never grows past its own
    /// content — otherwise a panel holding two widgets would be as tall as the
    /// screen.
    @State private var gridHeight: CGFloat?
    /// A tab was just picked, so the grid's next measured height is written
    /// plain. The strip's selection slides on the press's own transaction; what
    /// is under it cuts, and so does the card. The measurement travels in a
    /// transaction of its own, so the press's curve cannot reach it. Cleared
    /// 150 ms after the pick (chosen by eye); the next switch restarts it.
    @State private var cutsGridHeight = false
    @State private var cutsGridHeightClear: Task<Void, Never>?
    /// The pinned parts, measured rather than derived: what is pinned changes
    /// with the mode, and the grid gets whatever is left.
    @State private var topChrome: CGFloat?
    @State private var footerHeight: CGFloat?
    /// The tile in the air, and everything the overlay needs to draw it.
    @State private var dragging: Widget?
    /// Pointer location in the grid's own space.
    @State private var dragLocation: CGPoint = .zero
    /// Where inside the tile it was picked up, so the tile stays in the hand
    /// rather than snapping its corner to the pointer.
    @State private var grabOffset: CGSize = .zero
    /// The tile's size at pickup — the overlay draws at exactly this.
    @State private var dragSize: CGSize = .zero
    /// True for the landing: the overlay is gliding into its slot and the
    /// lift comes off.
    @State private var dropping = false
    /// The slot showing the grey well. Separate from `dragging` because the
    /// well outlives the drag: the exact handover swaps the content with
    /// animations disabled, and the well has to be free to fade on its own
    /// clock *after* that.
    @State private var well: String?
    /// Every tile's rectangle in the grid's space, which is how the drag knows
    /// what it is over.
    @State private var frames: [String: CGRect] = [:]
    /// Where the grid sits in the strip, so the overlay — which lives outside
    /// the scroll view — can translate pointer coordinates into its own.
    @State private var gridOrigin: CGPoint = .zero
    /// The tab whose glyph is being chosen, if any.
    @State private var pickingGlyph: String?
    @State private var renaming: String?
    @State private var draftName = ""
    @State private var diskAccess: PermissionState = .granted
    @State private var accessibility: PermissionState = .granted
    @State private var screenRecording: PermissionState = .granted

    /// What a widget is made of.
    ///
    /// The utilities list is not an `AnyView`, and that is the point of this
    /// enum. `AnyView` erases the type, so SwiftUI cannot match the old subtree
    /// to the new one and rebuilds it, `@State` included. That state is the
    /// measured height the list's disclosure animates between; erased, the
    /// list would jump from nothing to full size on every pass.
    ///
    /// A module's tile arrives as `AnyView` from its descriptor and stays so.
    private enum WidgetContent {
        case module(AnyView)
        /// The rows it holds travel with it, so nothing downstream has to ask
        /// `candidates` a second time to draw a widget it was already handed.
        case utilities([ModuleHost.Live])
    }

    /// One widget, at the size it ended up with.
    private struct Widget: Identifiable {
        let id: String
        let content: WidgetContent
        let size: PanelWidgetSize
        /// The sizes this module offers, in the grid's order, asked once where
        /// the widget is built: `body` re-runs on every pointer move of a drag.
        var offered: [PanelWidgetSize] = []
        /// Arrives by itself and cannot be taken off — the permissions notice
        /// is the only one, and it leaves when the grant is given.
        var pinned = false
    }

    /// What the panel can draw right now, computed once per pass in `body` and
    /// handed down. Never a computed property read from a subview: see
    /// `Widget.offered`.
    private struct Candidates {
        var byID: [String: ModuleHost.Live] = [:]
        var order: [String] = []
        var utilities: [ModuleHost.Live] = []
        /// Everything the drawer *could* hold, ticked or not — what the pencil
        /// offers. Its rows are the same rows; the difference is that a hidden
        /// module is in this list and not in the other.
        var choosable: [ModuleHost.Live] = []
    }

    /// The one widget that belongs to no module. This is why `Slot.widget` is
    /// an id rather than a module id.
    static let permissionsWidget = "helm.permissions"
    /// The drawer, which is a widget too: it is dragged, ordered and taken off
    /// like the others, and the only thing it does differently is that its
    /// corner control chooses *contents* rather than proportions.
    static let utilitiesWidget = "helm.utilities"

    /// What a fresh install is handed: full widths. A lone 1×1 tile leaves half
    /// its row empty; 1×1 is a choice for two things worth putting side by side.
    ///
    /// Only ever read when there is no stored layout at all: nobody's panel is
    /// rearranged by an update.
    static let seededSizes: [String: PanelWidgetSize] = [utilitiesWidget: .tall]

    // MARK: - What the panel can draw right now

    /// Modules that offer a widget, and the ones whose UI lives in Settings.
    /// One pass — building a widget builds a view, so each module is asked once.
    private var candidates: Candidates {
        var found = Candidates()
        for live in host.enabledModules {
            guard let contribution = live.menuBar() else { continue }
            let id = live.descriptor.idRaw
            // The drawer holds everything that is not a tile: a module with no
            // widget, and a module whose widget was taken off. «Not a tile» and
            // «not here» are different answers; one list saying both would make
            // taking a widget off look like deleting the module.
            if contribution.isUtility || layout.isDismissed(id) {
                found.choosable.append(live)
                if !layout.isHidden(id) { found.utilities.append(live) }
                if !contribution.isUtility { found.byID[id] = live }   // it can be promoted back
                continue
            }
            found.byID[id] = live
            found.order.append(id)
        }
        return found
    }

    /// The stored arrangement decides what is drawn and in what order; the live
    /// modules decide what *can* be drawn.
    /// Never stored: it arrives while a grant is missing and leaves with it,
    /// so putting it in the layout would mean writing a row that has to be
    /// deleted again the moment somebody presses Grant — and deciding, on
    /// every read, whether an absent one was removed or never added.
    ///
    /// It leaves with the grant because the grants are re-read on every
    /// opening (`.helmPanelDidShow`); this view is mounted once for the life
    /// of the app, so `onAppear` would read them once.
    private var permissionsWidget: Widget? {
        let missing = PermissionSummary.withheld(accessibility: accessibility, fullDisk: diskAccess,
                                                 screenRecording: screenRecording)
        guard !missing.isEmpty else { return nil }
        return Widget(id: Self.permissionsWidget,
                      content: .module(AnyView(PermissionsWidget(withheld: missing))),
                      size: .wide, pinned: true)
    }

    /// What the strip writes when a tab is picked: the tab, and the card's
    /// height told to follow without a curve, in the one transaction.
    private var pickedTab: Binding<Int> {
        Binding(get: { activeTab }, set: { tab in
            guard tab != activeTab else { return }
            cutsGridHeight = true
            activeTab = tab
            cutsGridHeightClear?.cancel()
            cutsGridHeightClear = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                cutsGridHeight = false
            }
        })
    }

    private var tabIndex: Int { activeTab.clamped(to: 0...max(0, layout.tabs.count - 1)) }

    private func widgets(_ parts: Candidates) -> [Widget] {
        let slots = layout.tabs.indices.contains(tabIndex) ? layout.tabs[tabIndex].widgets : []
        let placed: [Widget] = slots.compactMap { slot in
            if slot.widget == Self.utilitiesWidget {
                // One size. «How much room does the list of everything else
                // take» is not a question with three answers.
                return Widget(id: slot.widget,
                              content: .utilities(choosingUtilities ? parts.choosable
                                                                    : parts.utilities),
                              size: .tall)
            }
            guard let live = parts.byID[slot.widget] else {
                // A module that is switched off keeps its place and says so:
                // switching it off is not a request to rearrange the panel.
                guard let descriptor = ModuleRegistry.descriptor(slot.widget),
                      !ModuleHost.shared.isEnabled(descriptor) else { return nil }
                return Widget(id: slot.widget,
                              content: .module(AnyView(DisabledModuleWidget(descriptor: descriptor))),
                              size: slot.size)
            }
            let offered = live.panelWidgetSizes()
            guard let size = PanelGrid.resolve(slot.size, offered: offered),
                  let view = live.panelWidget(size) else { return nil }
            return Widget(id: slot.widget, content: .module(view), size: size,
                          offered: PanelWidgetSize.allCases.filter { offered.contains($0) })
        }
        // At the top, always: it is the only thing in the panel that is wrong
        // right now, and a notice must not need scrolling to.
        return [permissionsWidget].compactMap { $0 } + placed
    }

    private func reload() {
        layout = PanelLayoutStore.read(from: AppSettings.store,
                                       offered: candidates.order + [Self.utilitiesWidget],
                                       sizes: Self.seededSizes)
    }

    private func apply(_ next: PanelLayout) {
        layout = next
        // On every change, never on «Done»: the panel can close without Done
        // being pressed, by a click outside, Escape or the icon's own click.
        PanelLayoutStore.write(next, to: AppSettings.store)
    }

    // MARK: - The grid

    /// Rows of widgets, packed by `PanelGrid`.
    ///
    /// SwiftUI has no column span, so a full-width widget is a row of its own
    /// and compact ones share. `LazyVGrid` cannot express that, hence rows of
    /// `HStack`.
    @ViewBuilder
    private func grid(_ items: [Widget]) -> some View {
        let columns = PanelGrid.columns(for: helmPanelWidth)
        let rows = PanelGrid.rows(sizes: items.map(\.size), columns: columns)
        // Rows are keyed by position, and cannot be otherwise: `rows` is
        // `[[Int]]`, indices into `items`. A reorder rebuilds the rows, and a
        // widget moving between them is torn down and built again.
        //
        // What carries a tile across a reorder is `matchedGeometryEffect`
        // below: the frame travels even though the view does not. It is not
        // redundant; it is the whole mechanism.
        //
        // So a tile's `@State` does not survive a move between rows: the
        // drawer's measured height starts from zero again.
        ForEach(rows, id: \.self) { row in
            HStack(alignment: .top, spacing: PanelGrid.gap) {
                // By the widget, not by the index, so a cell keeps its identity
                // across a repack within a row. The drag gesture lives on the
                // container (`gridDrag`), so a rebuilt cell cannot kill it.
                ForEach(row.map { items[$0] }) { item in
                    cell(item)
                        // Two 1×1s in one row are one height.
                        .frame(maxHeight: .infinity)
                        // One rectangle across the change, so repacking the row
                        // *moves* the tile: a widget going from half a row to a
                        // whole one slides and stretches rather than vanishing
                        // from one place and appearing in another.
                        .matchedGeometryEffect(id: item.id, in: widgetShapes)

                }
                // A part-filled last row keeps its tiles their own width
                // instead of stretching them across the gap.
                if row.count < columns, !row.contains(where: { items[$0].size.isFullWidth }) {
                    ForEach(row.count..<columns, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ widget: Widget) -> some View {
        if widget.pinned {
            // No edit chrome and no badge: the one tile you cannot act on
            // should not wear an extra mark.
            body(of: widget)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
        body(of: widget)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .modifier(EditChrome(active: editing, size: widget.size,
                                 sizes: widget.offered,
                                 lifted: dragging?.id == widget.id,
                                 wellVisible: well == widget.id,
                                 // The drawer's rows must stay pressable while
                                 // its pencil is choosing them; everything else
                                 // is arrangement, not use.
                                 shielded: editing && !(widget.id == Self.utilitiesWidget
                                                        && choosingUtilities),

                                 // The drawer chooses contents, not proportions.
                                 // On a transaction, because the pencil swaps
                                 // the row set — two rows for nine — and the
                                 // block's measured height animates around it.
                                 choose: widget.id == Self.utilitiesWidget
                                     ? { withAnimation(HelmMotion.disclosure) {
                                             choosingUtilities.toggle()
                                         } } : nil,
                                 choosing: choosingUtilities,
                                 // One transaction: a size change swaps the
                                 // content, repacks the row and shifts every
                                 // tile below, and they must read as one move.
                                 resize: { size in
                                     withAnimation(HelmMotion.disclosure) {
                                         apply(layout.resizing(widget.id, to: size))
                                     }
                                 },
                                 remove: {
                                     withAnimation(HelmMotion.disclosure) {
                                         apply(layout.removing(widget.id))
                                     }
                                 },
                                 move: { offset in nudge(widget.id, by: offset) }))
            // Its rectangle, so the container's drag knows what is where —
            // both for picking a tile up and for knowing what the pointer is
            // over.
            .onGeometryChange(for: CGRect.self,
                              of: { $0.frame(in: .named(Self.gridSpace)) }) { rect in
                if frames[widget.id] != rect { frames[widget.id] = rect }
            }
        }
    }

    /// The drawer, at the one size it has. Its rows arrive with the widget, so
    /// `candidates` is not asked again per widget per pass.
    private func utilitiesSection(_ modules: [ModuleHost.Live]) -> some View {
        UtilitiesSection(modules: modules,
                         expanded: $utilitiesExpanded,
                         editing: editing,
                         choosing: choosingUtilities,
                         isOn: { !layout.isHidden($0) },
                         toggle: { id in
                             // A tick removes or restores a row, and the block
                             // measures its own height: without a transaction
                             // the rows below it jump.
                             withAnimation(HelmMotion.disclosure) {
                                 apply(layout.isHidden(id) ? layout.restoring(id)
                                                           : layout.hiding(id))
                             }
                         },
                         )
    }

    /// The one branch that keeps a concrete type — see `WidgetContent`.
    @ViewBuilder
    private func body(of widget: Widget) -> some View {
        Group {
            switch widget.content {
            case .module(let view): view
            case .utilities(let modules): utilitiesSection(modules)
            }
        }
        // No key on the size, deliberately: a key makes every resize a removal
        // and an insertion, so the tile cross-fades. A widget that takes its
        // size as a parameter is the same view type at 1×1 and 2×1, and SwiftUI
        // interpolates it.
        //
        // Where two sizes are different types (Keep Awake's compact figure
        // against its full tile) there is nothing to interpolate, so the new
        // content scales up from the card's anchored corner.
        .transition(.asymmetric(
            insertion: .scale(scale: 0.94, anchor: .topLeading).combined(with: .opacity),
            removal: .opacity))
    }

    nonisolated static let gridSpace = "panel.grid"
    nonisolated static let stripSpace = "panel.strip"

    /// Carrying a tile. An overlay rides the pointer rather than the tile
    /// moving itself: the tile's offset would be derived from frames a
    /// geometry callback has not delivered yet. The gesture lives on the grid
    /// container, which nothing rebuilds: on a cell, a reorder would rebuild
    /// it mid-drag, `onEnded` would never come, and the tile would hang in the
    /// air. Which tile was picked up is read from the frames at the start
    /// location; the cleanup is an animation completion rather than a timer.
    ///
    /// The three decisions inside — which frames are still real, which tile is
    /// under the pointer, and whether the pointer has travelled far enough to
    /// swap — are `PanelDrag`. What stays here is the state and the order it
    /// changes in.
    private func gridDrag(items: [Widget]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.gridSpace))
            .onChanged { value in
                // Frames of tiles that are no longer drawn, thrown away here
                // because nothing else will — `PanelDrag.pruned` carries the
                // reason, and answers nothing when there is nothing to throw
                // away, which is every move but the one after a tile goes.
                if let kept = PanelDrag.pruned(frames: frames, live: Set(items.map(\.id))) {
                    frames = kept
                }
                if dragging == nil {
                    guard let hit = PanelDrag.hit(frames: frames, at: value.startLocation),
                          let widget = items.first(where: { $0.id == hit.id })
                    else { return }
                    // The frames are measured outside `EditChrome`, which pads
                    // every tile by `EditChrome.overhang` in this mode. The
                    // overlay draws the content, so it takes the inset size, or
                    // it would land bigger than its slot and snap at the handover.
                    let content = hit.frame.insetBy(dx: EditChrome.overhang, dy: EditChrome.overhang)
                    dragSize = content.size
                    grabOffset = CGSize(width: value.startLocation.x - content.minX,
                                        height: value.startLocation.y - content.minY)
                    dropping = false
                    withAnimation(HelmMotion.reorder) { dragging = widget }
                    well = widget.id
                }
                guard let carried = dragging else { return }
                dragLocation = value.location

                // The slot under the pointer, if it is a different one —
                // checked against live frames, so the boundary between two
                // tiles is exactly where the neighbour starts to move.
                guard let over = PanelDrag.hit(frames: frames,
                                               at: value.location,
                                               excluding: carried.id),
                      let target = layout.placement(of: over.id),
                      let here = layout.placement(of: carried.id),
                      here.tab != target.tab || here.index != target.index else { return }

                // Past the middle, not merely inside — `PanelDrag.crossed` is
                // the hysteresis, and the oscillation it stops.
                let slot = frames[carried.id] ?? over.frame
                guard PanelDrag.crossed(from: slot, to: over.frame,
                                        pointer: value.location) else { return }
                withAnimation(HelmMotion.reorder) {
                    apply(layout.moving(carried.id, toTab: target.tab, at: target.index))
                }
            }
            .onEnded { _ in
                guard let carried = dragging else { return }
                // The glide home: to the slot the layout has already assigned,
                // lift coming off on the way. The handover to the real tile
                // happens in the completion: a timer knows neither when the
                // spring is done nor whether a new drag has started since.
                // The slot can be gone: switch a module off in Settings with
                // its tile in the air and `reload` takes the widget out from
                // under the drag. With nowhere to glide, the copy fades.
                guard let slot = frames[carried.id] else {
                    withAnimation(HelmMotion.interface) {
                        dragging = nil
                        dropping = false
                    }
                    well = nil
                    return
                }
                // `.removed`, not `.logicallyComplete`: the logical end comes
                // before the spring's visible tail, and a handover there cuts
                // the last frame of the landing.
                withAnimation(HelmMotion.reorder, completionCriteria: .removed) {
                    dropping = true
                    dragLocation = dropPoint(in: slot)
                } completion: {
                    // `dropping` is false if a new drag began mid-glide; the
                    // new drag owns the state now.
                    guard dropping else { return }
                    // An exact handover, with no fade: two copies at half alpha
                    // do not add back to one over a background, so a cross-fade
                    // dims the tile. The slot's frame is re-read after every
                    // spring has settled, the overlay is put exactly there, and
                    // the swap happens with animation off: the same pixels,
                    // drawn by someone else.
                    withTransaction(\.disablesAnimations, true) {
                        if let frame = frames[carried.id] {
                            dragLocation = dropPoint(in: frame)
                        }
                        dragging = nil
                        dropping = false
                    }
                    // Outside the disabled transaction, on purpose: the content
                    // swaps exactly, and the grey well under it fades on its own
                    // clock, through the scoped animation that watches it.
                    well = nil
                }
            }
    }

    /// The one full-weight copy of the tile in the air, above the grid, under
    /// the pointer.
    @ViewBuilder
    private var dragOverlay: some View {
        if let carried = dragging {
            body(of: carried)
                .frame(width: dragSize.width, height: dragSize.height)
                .scaleEffect(dropping ? 1 : 1.035)
                .shadow(color: .black.opacity(dropping ? 0 : 0.28),
                        radius: dropping ? 0 : 10, y: dropping ? 0 : 4)
                .offset(x: gridOrigin.x + dragLocation.x - grabOffset.width,
                        y: gridOrigin.y + dragLocation.y - grabOffset.height)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Where the carried copy's pointer sits when it is laid over a slot: the
    /// slot's frame inset by the overhang, plus the grab offset.
    private func dropPoint(in frame: CGRect) -> CGPoint {
        let home = frame.insetBy(dx: EditChrome.overhang, dy: EditChrome.overhang)
        return CGPoint(x: home.minX + grabOffset.width, y: home.minY + grabOffset.height)
    }

    /// Keyboard reordering. The panel is reachable from the keyboard and the
    /// edit mode must not be the one place that is not. A nudged tile travels
    /// on the same curve as a dragged one.
    private func nudge(_ id: String, by offset: Int) {
        guard let at = layout.placement(of: id) else { return }
        withAnimation(HelmMotion.reorder) {
            apply(layout.moving(id, toTab: at.tab, at: max(0, at.index + offset)))
        }
    }

    // MARK: - Chrome

    /// The namespace the tab selection travels in.
    @Namespace private var tabSelection
    /// And the one the tiles travel in — the gallery's ghosts too, so pressing
    /// one moves it into the grid.
    @Namespace private var widgetShapes

    /// Each of these is asked twice, once to draw the bar and once to take its
    /// height off what the grid may have, so each is spelled once: two copies
    /// out of step reserve room under a bar that is not drawn.
    private var showsTabStrip: Bool { layout.showsTabBar || editing }
    /// Nothing pinned means nothing to pin: three hidden buttons would
    /// otherwise leave an empty row at the foot of the panel.
    private var showsFooter: Bool { showSettingsButton || showQuitButton || showEditButton }
    /// The setup bar and the footer are measured together, and the setup bar is
    /// there whenever the mode is.
    private var showsFooterBlock: Bool { editing || showsFooter }

    /// Everything that could be a tile and is not one, in registry order so the
    /// row does not reshuffle between openings, the drawer among them.
    ///
    /// This asks only *is it a tile*; whether it is a row in the utilities
    /// list is the drawer's pencil's question, so a module can be both.
    ///
    /// Plain, not a `@ViewBuilder`: a builder reads `if` as a view, and an
    /// `append` inside one is a statement returning `()`, which is not a view.
    private func galleryIDs(_ byID: [String: ModuleHost.Live]) -> [String] {
        let placed = Set(layout.allSlots.map(\.widget))
        var rest = ModuleRegistry.all.map(\.idRaw)
            .filter { byID[$0] != nil && !placed.contains($0) }
        if !placed.contains(Self.utilitiesWidget) { rest.append(Self.utilitiesWidget) }
        return rest
    }

    var body: some View {
        // Once per pass, here: `candidates` walks every enabled module, reads
        // `UserDefaults`, decodes the sidebar's layout and builds a tile for
        // each, and `body` re-runs on every pointer move of a drag.
        let parts = candidates
        let items = widgets(parts)
        return VStack(spacing: 0) {
            card(parts, items)
            // Transparent filler: the window spans a strip, so a click below the
            // card should dismiss (a menu behaves the same way).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    NotificationCenter.default.post(name: .helmPanelDismissRequested, object: nil)
                }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: Self.stripSpace)
        .helmRoot()
        // Above everything and clipped by nothing: inside the scroll view its
        // bounds would cut the carried tile off at the grid's edge.
        .overlay(alignment: .topLeading) { dragOverlay }
        // The strip runs from the status item to the bottom of the screen, so
        // this is how much room the card has, on this display and this
        // position of the icon.
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { measured in
            if measured > 0, stripHeight != measured { stripHeight = measured }
        }
        // A new identity, not a redraw (`languageRevision`).
        .id(languageRevision)
        .onReceive(NotificationCenter.default.publisher(for: .helmLanguageChanged)) { _ in
            languageRevision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .helmModuleOrderChanged)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .helmMenuBarStyleChanged)) { _ in
            showEditButton = AppSettings.shows(.edit)
            showSettingsButton = AppSettings.shows(.settings)
            showQuitButton = AppSettings.shows(.quit)
        }
        // Every opening, not only the first: the view is built once and stays
        // mounted between them, so `onAppear` fires exactly once in a session
        // and a transition would never play again.
        //
        // Two turns, deliberately. Setting the start state and animating to the
        // end in one update is one update — SwiftUI coalesces them and there is
        // nothing to interpolate from.
        .onReceive(NotificationCenter.default.publisher(for: .helmPanelDidShow)) { _ in
            // Back to the first tab on every opening (see `activeTab`): this
            // view is mounted once at launch.
            activeTab = 0
            revealed = false
            // `reload` because a module switched on in Settings posts
            // `.helmModuleEnabled`, not `.helmModuleOrderChanged`, and its
            // widget must have a slot the first time the panel is opened.
            // The grants are re-read on this same notification, by the trackers
            // at the foot of this chain.
            reload()
            DispatchQueue.main.async {
                withAnimation(HelmMotion.panelEntrance) { revealed = true }
            }
        }
        // Asked for from the icon's menu, which is the door that cannot be
        // switched off.
        .onReceive(NotificationCenter.default.publisher(for: .helmPanelEditRequested)) { _ in
            withAnimation(HelmMotion.disclosure) { editing = true }
        }
    }

    /// Everything between the pinned bars: the grid, the gallery, the drawer.
    @ViewBuilder
    private func scrollable(_ parts: Candidates, _ items: [Widget]) -> some View {
            // Two different sentences: no module offers anything, or this tab
            // is empty. `order` excludes what was taken off a tile, so an
            // emptied panel or a new tab is the second case, whose way back is
            // the pencil, not Settings.
            if parts.byID.isEmpty && items.isEmpty && !editing {
                emptyState("square.grid.2x2", AppStr.noModules, AppStr.noModulesHint)
            } else if items.isEmpty && !editing {
                emptyState("rectangle.on.rectangle", AppStr.nothingOnThisTab,
                           showEditButton ? AppStr.nothingOnThisTabHint
                                          : AppStr.nothingOnThisTabHintNoButton)
            } else {
                grid(items)
                    // Keyed to the tab, so switching is a swap the transition
                    // can see rather than a list that happens to differ.
                    .id(layout.tabs.indices.contains(tabIndex) ? layout.tabs[tabIndex].id : "none")
                    // A cut, and not a fade: tabs switch sharply everywhere.
                    // Only the strip's selection plate moves. The identity
                    // transition is stated because a view replaced in an
                    // animated transaction cross-fades by default.
                    .transition(.identity)
                    .transaction(value: activeTab) { $0.animation = nil }
                // Shown only when there is something in it.
                let ghosts = editing ? galleryIDs(parts.byID) : []
                if !ghosts.isEmpty {
                    PanelGallery(ids: ghosts, byID: parts.byID, shapes: widgetShapes) { id in
                        // A tile again: `adding` clears both refusals and gives
                        // it a slot.
                        withAnimation(HelmMotion.disclosure) {
                            apply(layout.adding(id, toTab: tabIndex))
                        }
                    }
                }
            }
    }

    private func emptyState(_ symbol: String, _ title: String, _ hint: String) -> some View {
        VStack(spacing: HelmSpace.s4) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(HelmText.quiet)
            Text(title).font(HelmText.sectionHeading)
            Text(hint)
                .helmQuietDetail()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// What the grid may take. The arithmetic — and the rule that a bar nobody
    /// draws reserves nothing — is `PanelGrid.roomForGrid`; what stays here is
    /// which bars are on screen.
    private var availableForGrid: CGFloat {
        // `?? 0`, not the bare optional: `roomForGrid` reads `nil` as «this
        // bar is not drawn» and takes its gap away with it, so a bar that is
        // drawn and not yet measured arrives as 0.
        PanelGrid.roomForGrid(strip: stripHeight,
                              top: showsTabStrip ? (topChrome ?? 0) : nil,
                              foot: showsFooterBlock ? (footerHeight ?? 0) : nil)
    }

    private func card(_ parts: Candidates, _ items: [Widget]) -> some View {
        VStack(alignment: .leading, spacing: PanelGrid.gap) {

            // Pinned: the strip, the setup bar and the footer. Only the grid
            // scrolls: the way out of a mode must not need scrolling to, and in
            // edit mode every widget grows a frame and corner controls.
            // Only when there is something pinned: an empty `VStack` has no
            // height, but the stack around it still puts `PanelGrid.gap` after
            // it, and the top edge would get more than `PanelGrid.padding`.
            if showsTabStrip {
                PanelTabStrip(layout: layout, tabIndex: tabIndex, editing: editing,
                              selection: tabSelection,
                              activeTab: pickedTab, pickingGlyph: $pickingGlyph,
                              rename: { tab, current in
                                  draftName = current
                                  renaming = tab
                              },
                              apply: apply)
                    // In a transaction, like the grid's height: this changes
                    // when the mode is entered, and a raw write would snap the
                    // panel's ends while its middle animates.
                    .helmMeasuredHeight($topChrome)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PanelGrid.gap) {
                    scrollable(parts, items)
                }
                .coordinateSpace(name: Self.gridSpace)
                // On the container, which nothing rebuilds — see `gridDrag`.
                .gesture(editing ? gridDrag(items: items) : nil)
                // Where the grid is, in the strip's space: the overlay draws
                // out there, past the scroll view's clip.
                .onGeometryChange(for: CGPoint.self,
                                  of: { $0.frame(in: .named(Self.stripSpace)).origin }) { origin in
                    if gridOrigin != origin { gridOrigin = origin }
                }
                // The measurement travels in a transaction so the card grows
                // with the list it holds; the law is on `helmMeasuredHeight`.
                //
                // The first measurement is plain: until it lands the scroll
                // view takes everything it is offered (the whole strip), so
                // animating that first write would play the card collapsing
                // from full height to its content.
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { measured in
                    // `helmMeasuredHeight`'s law, with one exception that is this
                    // panel's own: right after a tab is picked the write is
                    // plain. The first measurement is plain for the same reason.
                    guard measured > 0, gridHeight != measured else { return }
                    if gridHeight == nil || cutsGridHeight {
                        withTransaction(\.disablesAnimations, true) { gridHeight = measured }
                    } else {
                        withAnimation(HelmMotion.disclosure) { gridHeight = measured }
                    }
                }
            }
            // An explicit height, not a `maxHeight`: a `ScrollView`'s ideal
            // height is not its content's, and it would clip the grid while the
            // card had room to spare. This is the smaller of what the grid
            // needs and what the strip has left.
            .frame(height: gridHeight.map { min($0, availableForGrid) })
            .scrollIndicators(.automatic)
            // Where the grid is taller than the room it has, the clipped edge
            // says so: a widget cut by the clip otherwise reads as a short
            // widget, and the bars and the list as one flat sheet.
            .helmPanelScrollEdges()
            // The way out of the mode sits with the other two exits (Settings
            // and Quit), at the foot of the panel.
            VStack(alignment: .leading, spacing: PanelGrid.gap) {
                if editing {
                    PanelEditBar {
                        // The same curve as the way in.
                        withAnimation(HelmMotion.disclosure) {
                            editing = false
                            choosingUtilities = false
                        }
                    }
                }
                if showsFooter {
                    PanelFooter(editing: editing, showSettings: showSettingsButton,
                                showQuit: showQuitButton, showEdit: showEditButton) {
                        // The same curve the card's measured height animates on:
                        // entering the mode grows every cell by twice
                        // `EditChrome.overhang`, so the grid's height changes
                        // with it, and two curves for one event judder.
                        withAnimation(HelmMotion.disclosure) { editing = true }
                    }
                }
            }
            .helmMeasuredHeight($footerHeight)
        }
        .padding(PanelGrid.padding)
        .frame(width: helmPanelWidth)
        // A fade, and nothing else: macOS menus and menu-bar extras do not
        // grow, scale or slide into place.
        .opacity(revealed ? 1 : 0)
        // No `maxHeight` here: it takes what the parent proposes, a strip
        // running to the bottom of the screen, and a short panel would draw a
        // card that tall. The scroll view is the one thing allowed to give way
        // (`availableForGrid`); everything else is its own size.
        .alert(HelmWord.rename, isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField(AppStr.tabLabel, text: $draftName)
            Button(HelmWord.done) {
                if let id = renaming { apply(layout.renamingTab(id, to: draftName)) }
                renaming = nil
            }
            Button(HelmWord.cancel, role: .cancel) { renaming = nil }
        }
        .onAppear { reload() }
        // `alsoOn` because the panel takes key focus without activating the
        // app, so opening it posts no `didBecomeActive`, and this view is
        // mounted once, so `.task` fires once for the life of the process.
        .helmTracksFullDiskAccess($diskAccess, alsoOn: .helmPanelDidShow)
        .helmTracksAccessibility($accessibility, alsoOn: .helmPanelDidShow)
        .helmTracksScreenRecording($screenRecording, alsoOn: .helmPanelDidShow)
        // Liquid Glass, and no border of our own: glass supplies its specular
        // edge. `HelmRadius.panel` is the tile cards' `HelmRadius.frame` plus
        // the `PanelGrid.padding` they sit in, so the radii are concentric and
        // read as nested.
        .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.panel))
        .containerShape(.rect(cornerRadius: HelmRadius.panel))
        // Centred in a strip that is wider than the card, so the glass has
        // somewhere to cast. After the glass: before it, the effect would
        // paint the whole strip.
        .frame(maxWidth: .infinity)
        // Pin the card to the TOP of the hosting bounds: while window and content
        // sizes momentarily disagree, the slack stays at the transparent bottom
        // instead of the default centering, which read as the card dropping.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
