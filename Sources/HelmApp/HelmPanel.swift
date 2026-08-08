import AppKit
import SwiftUI
import HelmRuntime
import HelmUI

/// Internal rather than private so a test can render it: the panel is a
/// menu-bar window over Liquid Glass, and there is no other way to look at it
/// without a screenshot of somebody's screen.
struct HelmPanelContent: View {
    @ObservedObject var host: ModuleHost
    @State private var utilitiesExpanded = false
    /// The panel is being arranged rather than read.
    ///
    /// Settable at construction only so a probe can render the mode: it is a
    /// menu-bar panel over Liquid Glass, and a mode nothing can draw offscreen
    /// is a mode nobody can measure.
    @State private var editing: Bool

    init(host: ModuleHost, editing: Bool = false) {
        self.host = host
        _editing = State(initialValue: editing)
    }
    @State private var layout = PanelLayout(tabs: [])
    /// Which tab is being looked at. Session state, not stored: the panel is
    /// opened for a glance, and opening it on the tab somebody happened to
    /// leave last week is a panel that answers a question nobody asked.
    @State private var activeTab = 0
    /// The strip the panel is drawn in, top to bottom of the screen. The card
    /// may not be taller than it, and the grid is what gives way.
    /// The card has played its entrance. Set false for the one frame the
    /// entrance animates from, then true again.
    ///
    /// **True to begin with**, not false. If the notification that plays the
    /// entrance ever failed to arrive — a probe hosting this view, a path that
    /// shows the window without going through `toggle` — starting at false
    /// would leave a panel drawn at zero opacity, which is a missing panel. The
    /// worst this way round is a missing animation.
    @State private var revealed = true
    /// The drawer is choosing its rows rather than showing them.
    @State private var choosingUtilities = false
    @State private var showEditButton = AppSettings.showPanelEditButton
    @State private var showSettingsButton = AppSettings.showSettingsButton
    @State private var showQuitButton = AppSettings.showQuitButton
    @State private var tabLabels = AppSettings.tabLabelStyle
    @State private var stripHeight: CGFloat = 0
    /// The grid's natural height, so the scroll view never grows past its own
    /// content — otherwise a panel holding two widgets would be as tall as the
    /// screen.
    @State private var gridHeight: CGFloat = 0
    /// The pinned parts, measured rather than derived: what is pinned changes
    /// with the mode, and the grid gets whatever is left.
    @State private var topChrome: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
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

    /// What a widget is made of.
    ///
    /// The utilities list is **not** an `AnyView`, and that is the whole point
    /// of this enum. `AnyView` erases the type, so SwiftUI cannot match the old
    /// subtree to the new one between updates — it rebuilds it, and the
    /// `@State` inside goes with it. That state is the measured height the
    /// list's disclosure animates between, so it was reset to zero on every
    /// pass and the list opened by jumping from nothing to its full size,
    /// taking the card with it.
    ///
    /// A module's tile can stay erased: it is handed over as `AnyView` by the
    /// descriptor and nothing here can un-erase it. What matters is that the
    /// one view *this file* owns is not.
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
        /// The sizes this module offers, in the grid's order — asked once,
        /// where the widget is built.
        ///
        /// It used to be a function the size control called, and that function
        /// opened with `candidates`: a `UserDefaults` read, a JSON decode and a
        /// tile built for every module, per widget, per pass. `body` re-runs on
        /// every pointer move of a drag.
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
        var choosable: [ModuleHost.Live] = []
    }

    /// The one widget that belongs to no module. This is why `Slot.widget` is
    /// an id rather than a module id.
    static let permissionsWidget = "helm.permissions"
    /// The drawer, which is a widget too: it is dragged, ordered and taken off
    /// like the others, and the only thing it does differently is that its
    /// corner control chooses *contents* rather than proportions.
    static let utilitiesWidget = "helm.utilities"

    /// What a fresh install is handed.
    ///
    /// Disk was seeded at 1×1 for a day, on the argument that a square shows
    /// what the grid is for — and that argument was about *pairing*: two
    /// squares sharing a row. When Autopilot and Layout went back to being rows
    /// in the list there was nothing left to pair it with, so the square sat
    /// alone with its right half empty, which demonstrates the grid by showing
    /// a hole in it.
    ///
    /// Three widgets, three full widths. 1×1 is a choice somebody makes when
    /// they have two things worth putting side by side.
    ///
    /// Only ever read when there is no stored layout at all: nobody's panel is
    /// rearranged by an update.
    static let seededSizes: [String: PanelWidgetSize] = [utilitiesWidget: .tall]

    // MARK: - What the panel can draw right now

    /// Modules that offer a widget, and the ones whose UI lives in Settings.
    /// One pass — building a widget builds a view, so each module is asked once.
    private var candidates: Candidates {
        var byID: [String: ModuleHost.Live] = [:]
        var order: [String] = []
        var utilities: [ModuleHost.Live] = []
        /// Everything the drawer *could* hold, ticked or not — what the pencil
        /// offers. Its rows are the same rows; the difference is that a hidden
        /// module is in this list and not in the other.
        var choosable: [ModuleHost.Live] = []
        for live in host.enabledModules {
            guard let contribution = live.descriptor.menuBar(live.vm) else { continue }
            let id = live.descriptor.idRaw
            // The drawer holds everything that is not a tile — a module with no
            // widget, and a module whose widget was taken off. «Not a tile» and
            // «not here» are different answers, and one list saying both is
            // what made taking a widget off look like deleting the module.
            if contribution.isUtility || layout.isDismissed(id) {
                choosable.append(live)
                if !layout.isHidden(id) { utilities.append(live) }
                if !contribution.isUtility { byID[id] = live }   // it can be promoted back
                continue
            }
            byID[id] = live
            order.append(id)
        }
        return Candidates(byID: byID, order: order,
                          utilities: utilities, choosable: choosable)
    }

    /// The stored arrangement decides what is drawn and in what order; the live
    /// modules decide what *can* be drawn.
    /// Never stored: it arrives while a grant is missing and leaves with it,
    /// so putting it in the layout would mean writing a row that has to be
    /// deleted again the moment somebody presses Grant — and deciding, on
    /// every read, whether an absent one was removed or never added.
    ///
    /// «Leaves with it» is true because the two grants are re-read on every
    /// opening. It was not: the probes ran from `onAppear`, this view is
    /// mounted once for the life of the app, and a notice that had been
    /// answered stayed pinned to the top of the panel until the next launch.
    private var permissionsWidget: Widget? {
        let missing = PermissionSummary.withheld(accessibility: accessibility, fullDisk: diskAccess)
        guard !missing.isEmpty else { return nil }
        return Widget(id: Self.permissionsWidget,
                      content: .module(AnyView(PermissionsWidget(
                          withheld: missing, modules: PermissionSummary.affected(by: missing)))),
                      size: .wide, pinned: true)
    }

    private var tabIndex: Int { min(max(0, activeTab), max(0, layout.tabs.count - 1)) }

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
                // A module that is switched off keeps its place and says so.
                // Dropping the tile would take the arrangement apart and leave
                // nobody able to say where the block went — and switching a
                // module off is not a request to rearrange the panel.
                guard let descriptor = ModuleRegistry.all.first(where: { $0.idRaw == slot.widget }),
                      !ModuleHost.shared.isEnabled(descriptor) else { return nil }
                return Widget(id: slot.widget,
                              content: .module(AnyView(DisabledModuleWidget(descriptor: descriptor))),
                              size: slot.size)
            }
            let offered = live.descriptor.panelWidgetSizes(live.vm)
            guard let size = PanelGrid.resolve(slot.size, offered: offered),
                  let view = live.descriptor.panelWidget(size, live.vm) else { return nil }
            return Widget(id: slot.widget, content: .module(view), size: size,
                          offered: PanelWidgetSize.allCases.filter { offered.contains($0) })
        }
        // At the top, always. It is the only thing in the panel that is wrong
        // right now, and a notice somebody has to scroll to is a notice.
        return [permissionsWidget].compactMap { $0 } + placed
    }

    private func reload() {
        layout = PanelLayoutStore.read(from: AppSettings.store,
                                       offered: candidates.order + [Self.utilitiesWidget],
                                       sizes: Self.seededSizes)
    }

    private func apply(_ next: PanelLayout) {
        layout = next
        // On every change, never on «Done». There is no Done to wait for: the
        // panel closes when it loses focus, which is most of the ways out of it.
        PanelLayoutStore.write(next, to: AppSettings.store)
    }

    // MARK: - The grid

    /// Rows of widgets, packed by `PanelGrid`.
    ///
    /// SwiftUI has no column span, so a full-width widget is a row of its own
    /// and compact ones share. `LazyVGrid` cannot express that at all, which is
    /// why this is rows of `HStack` rather than a grid view.
    @ViewBuilder
    private func grid(_ items: [Widget]) -> some View {
        let columns = PanelGrid.columns(for: helmPanelWidth)
        let rows = PanelGrid.rows(sizes: items.map(\.size), columns: columns)
        // **Rows are keyed by position, and cannot be otherwise.** `rows` is
        // `[[Int]]` — indices into `items` — so `id: \.self` keys a row by the
        // slots it occupies, which for a panel of full-width tiles is exactly
        // its position. A reorder therefore does rebuild the rows, and a widget
        // moving between them is torn down and built again.
        //
        // What carries a tile across a reorder is `matchedGeometryEffect`
        // below: one rectangle either side of the change, so the frame travels
        // even though the view does not. Do not delete it as redundant — it is
        // the whole of the mechanism.
        //
        // The consequence to remember is that a tile's `@State` does not
        // survive a move between rows. The drawer's measured height is the one
        // that shows: reparented, it starts from zero again.
        ForEach(rows, id: \.self) { row in
            HStack(alignment: .top, spacing: PanelGrid.gap) {
                // By the widget, not by the index. Within a row this is what
                // keeps a cell's identity across a repack — and the gesture
                // that used to die mid-drag lives on the container now
                // (see `gridDrag`), which is the load-bearing half of that fix.
                ForEach(row.map { items[$0] }) { item in
                    cell(item)
                        // Two 1×1s in one row are one height. They were 95 and
                        // 89 — six points of ragged edge in a grid whose sizes
                        // are named after squares.
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
            // No badge in edit mode. It said «this cannot be removed», which is
            // a sentence about a control that is not there — and it hung off
            // the corner where every other widget has a minus, so the one tile
            // you cannot act on was the one wearing an extra mark.
            body(of: widget)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
        body(of: widget)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .modifier(EditChrome(active: editing, widget: widget.id, size: widget.size,
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
                                 // One transaction for the whole move. A size
                                 // change is three things at once — the tile
                                 // swaps its content, the row it is in repacks,
                                 // and every tile below shifts — and they have
                                 // to be one gesture or the panel reads as
                                 // three separate jumps.
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

    /// The drawer, at the one size it has. Its rows arrive with the widget —
    /// asking `candidates` from here is what made a computed property run once
    /// per widget per pass.
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
        // **No key on the size**, deliberately.
        //
        // Keying it made every resize a removal and an insertion, so the tile
        // cross-faded: two pictures dissolving where somebody had asked a
        // rectangle to change shape. A widget that takes its size as a
        // parameter — Disk does — is the *same view type* at 1×1 and 2×1, and
        // left unkeyed SwiftUI matches it and interpolates: the plate stays
        // put, the bar and the row grow out of the card, the card stretches.
        //
        // Where the two sizes are genuinely different types — Keep Awake's
        // compact figure against its full tile — there is nothing to
        // interpolate, so the new content scales up from the corner the card is
        // anchored by rather than arriving at full size.
        .transition(.asymmetric(
            insertion: .scale(scale: 0.94, anchor: .topLeading).combined(with: .opacity),
            removal: .opacity))
    }

    static let gridSpace = "panel.grid"
    static let stripSpace = "panel.strip"
    /// What `EditChrome` pads a tile by while the mode is on — the frames are
    /// measured outside it, and the drag needs the content rectangle.
    static let chromeInset: CGFloat = 4

    /// Carrying a tile — third architecture, and the reasons each of the first
    /// two failed are what this one is made of.
    ///
    /// The first moved the tile itself and stuttered, because its offset was
    /// re-derived from frames a geometry callback had not delivered yet. The
    /// second drew an overlay — right — but hung its gesture on the cell, and a
    /// reorder rebuilt the cells: the gesture died under the pointer, `onEnded`
    /// never came, and the widget was left hanging in the air.
    ///
    /// So: the overlay rides the pointer, and the gesture lives on the **grid
    /// container**, which nothing rebuilds. Which tile was picked up is read
    /// from the frames at the start location; the cleanup is an animation
    /// completion rather than a timer.
    ///
    /// The three decisions inside — which frames are still real, which tile is
    /// under the pointer, and whether the pointer has travelled far enough to
    /// swap — are `PanelDrag`, where they can be argued with in a test. What
    /// stays here is the state and the order it changes in.
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
                    // every tile by 4 pt in this mode — so the raw frame is the
                    // tile plus 8 pt each way. The overlay draws the *content*,
                    // and drawing it at the padded size inflated the carried
                    // tile just enough to be visibly bigger than the slot it
                    // lands in, with a snap down at the handover.
                    let content = hit.frame.insetBy(dx: Self.chromeInset, dy: Self.chromeInset)
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
                // happens in the completion — a timer used to do this, and a
                // timer neither knows when the spring is done nor whether a new
                // drag has started since.
                // The slot can be gone: switch a module off in Settings with
                // its tile in the air and `reload` takes the widget out from
                // under the drag. There is nowhere to glide to, so the copy in
                // the hand fades instead of being cut — the one exit from a
                // drag that had no motion at all.
                guard let home = frames[carried.id]?
                        .insetBy(dx: Self.chromeInset, dy: Self.chromeInset) else {
                    withAnimation(HelmMotion.interface) {
                        dragging = nil
                        dropping = false
                    }
                    well = nil
                    return
                }
                // `.removed`, not `.logicallyComplete`: the logical end comes
                // before the spring's visible tail, so the handover used to
                // happen while the overlay was still settling — a cut in the
                // last frame of the landing.
                withAnimation(HelmMotion.reorder, completionCriteria: .removed) {
                    dropping = true
                    dragLocation = CGPoint(x: home.minX + grabOffset.width,
                                           y: home.minY + grabOffset.height)
                } completion: {
                    // `dropping` is false if a new drag began mid-glide; the
                    // new drag owns the state now.
                    guard dropping else { return }
                    // An exact handover, with no fade at all.
                    //
                    // The cross-fade that was here read as a dip: two copies at
                    // half alpha do not add back to one over a background, so
                    // the tile dimmed for six frames on landing. A fade was
                    // covering for a position that might be a few points out —
                    // so fix the position instead. The slot's frame is re-read
                    // *now*, after every spring has settled, the overlay is put
                    // exactly there, and the swap happens in a transaction with
                    // animation off: the same pixels, drawn by someone else.
                    var settle = Transaction()
                    settle.disablesAnimations = true
                    withTransaction(settle) {
                        if let frame = frames[carried.id] {
                            let home = frame.insetBy(dx: Self.chromeInset, dy: Self.chromeInset)
                            dragLocation = CGPoint(x: home.minX + grabOffset.width,
                                                   y: home.minY + grabOffset.height)
                        }
                        dragging = nil
                        dropping = false
                    }
                    // Outside the disabled transaction, on purpose: the content
                    // must swap exactly, and the grey well under it must not —
                    // it fades out on its own clock, through the scoped
                    // animation that watches it. Killing both with one
                    // transaction was why the placeholder vanished in a frame.
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

    /// Keyboard reordering. The panel is reachable from the keyboard and the
    /// edit mode must not be the one place that is not.
    ///
    /// The same curve the pointer gets. It was a bare assignment, so the one
    /// path through the edit mode that did not animate at all was the keyboard:
    /// dragged, a tile travels on `reorder`; nudged, it teleported.
    private func nudge(_ id: String, by offset: Int) {
        guard let at = layout.placement(of: id) else { return }
        withAnimation(HelmMotion.reorder) {
            apply(layout.moving(id, toTab: at.tab, at: max(0, at.index + offset)))
        }
    }

    // MARK: - Chrome

    /// The strip, and it is the first row of the card **in both modes**.
    ///
    /// In the mockups' first version it stood first when reading and second
    /// when editing, so entering the mode moved every tab out from under the
    /// cursor that had just pressed one.
    /// The namespace the selection travels in.
    @Namespace private var tabSelection
    /// And the one the tiles travel in.
    @Namespace private var widgetShapes

    @ViewBuilder
    private var tabStrip: some View {
        if layout.showsTabBar || editing {
            HStack(spacing: 4) {
                ForEach(Array(layout.tabs.enumerated()), id: \.element.id) { index, tab in
                    Button {
                        // The strip and the grid move together: the selection
                        // slides while the widgets under it cross-fade, on one
                        // transaction rather than two.
                        withAnimation(HelmMotion.interface) { activeTab = index }
                    } label: {
                        // The mockup's tab: 4 pt between glyph and text, 4×8
                        // of padding, a 10 pt corner, and 11 pt type that does
                        // **not** change weight when selected.
                        //
                        // Weight was the first thing tried and it is the one
                        // thing a tab cannot do: bold is wider than regular, so
                        // every tab in the strip moved whenever another was
                        // picked. Selection is a background and a colour.
                        HStack(spacing: 4) {
                            if tabLabels.showsGlyph, let glyph = tab.glyph {
                                Image(systemName: glyph)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            if tabLabels.showsText {
                                Text(AppStr.tabTitle(tab, number: index + 1))
                                    .font(HelmText.rowDetail)
                                    .lineLimit(1)
                            }
                            // The way to a tab's own settings, on the tab that
                            // is open. The context menu has the same three
                            // items; a chevron is what says they are there.
                            if editing, index == tabIndex {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(HelmText.quiet)
                            }
                        }
                        .foregroundStyle(index == tabIndex ? Color.primary : HelmText.quiet)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background {
                            if index == tabIndex {
                                // A material, not a 5% overlay. `wellFill`
                                // measured 1.23:1 over the panel's glass and
                                // 1.04:1 in light — and the shadow under it was
                                // cast by a shape with 5% alpha, so it was
                                // ~0.6% black, which is nothing. A material
                                // composites against whatever is behind it,
                                // which is what a raised segment is.
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.regularMaterial)
                                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                                    // One shape that moves between tabs rather
                                    // than one appearing while another goes.
                                    .matchedGeometryEffect(id: "tab.selection", in: tabSelection)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    // Glyph-only tabs have nowhere to put their name; the
                    // pointer is where it goes.
                    .help(AppStr.tabTitle(tab, number: index + 1))
                    .accessibilityLabel(AppStr.tabTitle(tab, number: index + 1))
                    .contextMenu {
                        Button(AppStr.renameSection) {
                            draftName = AppStr.tabTitle(tab, number: index + 1)
                            renaming = tab.id
                        }
                        Button(AppStr.tabIcon) { pickingGlyph = tab.id }
                        Button(AppStr.closeTab, role: .destructive) {
                            // The token the tab buttons use. Bare, the content
                            // cut while the card's measured height went on
                            // ramping around it — its own transaction — so
                            // closing a tab looked unlike switching to one.
                            withAnimation(HelmMotion.interface) {
                                apply(layout.removingTab(tab.id))
                                activeTab = min(tabIndex, max(0, layout.tabs.count - 1))
                            }
                        }
                        .disabled(layout.tabs.count == 1)
                    }
                    .popover(isPresented: Binding(get: { pickingGlyph == tab.id },
                                                  set: { if !$0 { pickingGlyph = nil } }),
                             arrowEdge: .bottom) {
                        HelmGlyphPicker(selected: tab.glyph) { glyph in
                            apply(layout.settingGlyph(glyph, onTab: tab.id))
                            pickingGlyph = nil
                        }
                    }
                }
                if editing {
                    Button {
                        // The lowest number nobody is using. Counting the
                        // tabs breaks the moment one in the middle is closed:
                        // three tabs minus the second is two, and the next new
                        // one would ask for an id the third already has.
                        let taken = Set(layout.tabs.map(\.id))
                        var n = 2
                        while taken.contains("tab.\(n)") { n += 1 }
                        withAnimation(HelmMotion.interface) {
                            apply(layout.addingTab(id: "tab.\(n)"))
                            activeTab = layout.tabs.count - 1
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStr.newTab)
                }
                Spacer(minLength: 0)
            }
            // ⌘1…⌘9, as every tabbed window on the machine — on buttons of
            // their own rather than on the tabs.
            //
            // A `keyboardShortcut` on a button decorates that button's *context
            // menu* as well, so every item of the tab's menu — Rename, Icon,
            // Close — was drawn with a «⌘2» it did not have and would not obey.
            .background {
                ForEach(0..<min(layout.tabs.count, 9), id: \.self) { index in
                    Button("") { withAnimation(HelmMotion.interface) { activeTab = index } }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// The bar above the grid while the panel is being arranged.
    /// The bar says one thing: you are editing, and here is the way out.
    ///
    /// It carried the tab-label picker for a while — a full-width segmented
    /// control, the heaviest thing in the panel, for a decision somebody makes
    /// once, inside a mode that is about arranging widgets. It also appeared
    /// and vanished with the number of tabs, so it flickered on state it had
    /// nothing to do with, and it argued with «Готово» for the same row. It
    /// lives in Settings → Panel now, beside the other three switches about how
    /// this panel looks.
    private var editBar: some View {
        HStack(spacing: 8) {
            Text(AppStr.panelSetup).font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button(AppStr.done) {
                // The same curve as the way in. This was a bare assignment, so
                // entering the mode animated and leaving it cut — every cell
                // dropping its padding and its corner controls in one frame.
                withAnimation(HelmMotion.disclosure) {
                    editing = false
                    choosingUtilities = false
                }
            }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .helmPanelCard()
    }

    /// Everything that could be a tile and is not one, in registry order so the
    /// row does not reshuffle itself between openings — and the drawer among
    /// them, because it is a widget like the others.
    ///
    /// Two independent questions, and this is the first: *is it a tile*. The
    /// second — is it a row in the utilities list — is asked by that widget's
    /// own pencil. A module can be both a row there and an entry here, because
    /// «not a tile» and «not in the list» are not the same refusal.
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

    /// Everything not on this tab, as ghosts to press.
    @ViewBuilder
    private func gallery(_ byID: [String: ModuleHost.Live]) -> some View {
        let rest = galleryIDs(byID)
        // Shown only when there is something in it: a heading over a sentence
        // saying there is nothing to do belongs on no screen, least of all the
        // one where every other row is doing something.
        if !rest.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppStr.addWidget)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
            do {
                let columns = PanelGrid.columns(for: helmPanelWidth)
                ForEach(Array(stride(from: 0, to: rest.count, by: columns)), id: \.self) { start in
                    HStack(spacing: PanelGrid.gap) {
                        ForEach(rest[start..<min(start + columns, rest.count)], id: \.self) { id in
                            ghost(id, byID[id])
                        }
                        ForEach(0..<max(0, columns - (min(start + columns, rest.count) - start)),
                                id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
        }
        .helmPanelCard()
        }
    }

    private func ghost(_ id: String, _ live: ModuleHost.Live?) -> some View {
        let descriptor = live?.descriptor ?? ModuleRegistry.all.first { $0.idRaw == id }
        let isDrawer = id == Self.utilitiesWidget
        return Button {
            // A tile again: `adding` clears both refusals and gives it a slot,
            // which is what the drawer needs — it *is* a tile, and one that
            // only came here because somebody took it off.
            withAnimation(HelmMotion.disclosure) {
                apply(layout.adding(id, toTab: tabIndex))
            }
        } label: {
            VStack(spacing: 4) {
                if isDrawer {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HelmText.quiet)
                    Text(AppStr.utilities)
                        .font(HelmText.rowDetail)
                        .lineLimit(1)
                } else if let descriptor {
                    // 26, as the widget header draws it. The same module 200 pt
                    // apart in two sizes is the defect `HelmWidgetHeader` was
                    // unified to kill, reappearing in the gallery.
                    HelmIconPlate(symbol: descriptor.moduleMetadata.sfSymbol,
                                  tint: descriptor.moduleTint.colour, size: 26)
                    Text(descriptor.moduleMetadata.shortName)
                        .font(HelmText.rowDetail)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(HelmText.faint))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The same namespace the tiles travel in, so pressing a ghost *moves*
        // it into the grid instead of ending it here and starting it there.
        // Safe because the two can never be on screen together: `galleryIDs`
        // offers only what no tab holds, and a tile is drawn only where it is
        // held — so this id has exactly one view at any moment.
        .matchedGeometryEffect(id: id, in: widgetShapes)
    }

    /// Not an option any more.
    ///
    /// `showSettingsButton` and `showQuitButton` both defaulted to false, which
    /// is how a clean install ended up with no way into settings from the panel
    /// it was given — and no way to find the switch that would have added one.
    @ViewBuilder
    private var footer: some View {
        // Nothing pinned means nothing to pin: three hidden buttons would
        // otherwise leave an empty card at the foot of the panel.
        if showSettingsButton || showQuitButton || showEditButton {
        HStack(spacing: 8) {
            if showSettingsButton {
                footerButton(AppStr.settingsPane, "gearshape") {
                    NotificationCenter.default.post(name: .helmOpenSettings,
                                                    object: SettingsWindow.settingsPage)
                }
            }
            Spacer(minLength: 8)
            // Only on the way in. While the setup bar is on screen it carries
            // «Готово», and two of them a hundred points apart is one of them
            // asking whether the other did something else.
            //
            // A glyph, not a word. «Настроить панель» is the longest label in
            // the footer and the least often pressed — it is the door to a mode
            // somebody enters once and then leaves alone — and at 300 pt it was
            // the label that ran out of room and truncated to «Настроить па…».
            // A pencil is the one glyph macOS uses for exactly this, and the
            // name is still there for a pointer that rests on it and for
            // VoiceOver.
            // Both glyphs at the right edge, together. A lone icon floating
            // in the middle of a footer reads as something that lost its label
            // rather than as something that never needed one.
            if !editing && showEditButton {
                footerGlyph("pencil", AppStr.configurePanel) {
                    // The same curve the card's measured height animates on.
                    // Entering the mode grows every cell by 8 pt and adds two
                    // controls to each, so the grid's height changes with it —
                    // and on `interface` (0.22 snappy) against the height's
                    // `disclosure` (0.30 smooth) the tiles and the card they
                    // are in were running two different animations of the same
                    // event. That is the judder.
                    withAnimation(HelmMotion.disclosure) { editing = true }
                }
            }
            if showQuitButton {
                footerGlyph("power", AppStr.quit) { NSApp.terminate(nil) }
            }
        }
        .helmPanelCard()
        }
    }

    /// A footer action with no room for its name: the name is the tooltip and
    /// the accessibility label, which is the whole of what the word was doing.
    private func footerGlyph(_ symbol: String, _ name: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HelmText.quiet)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
    }

    private func footerButton(_ title: String, _ symbol: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(HelmText.quiet)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        // **Once per pass, here.** `candidates` walks every enabled module,
        // reads `UserDefaults`, decodes the sidebar's layout and builds a tile
        // for each — and it used to be read from `cell`, from `offeredSizes`
        // and from the drawer, so a six-widget panel paid for all of that seven
        // times over on every pointer move of a drag.
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
        // Above everything and clipped by nothing. It used to live inside the
        // scroll view, whose bounds cut the carried tile off at the grid's
        // edge — a thing in your hand disappearing behind the furniture it is
        // being carried over.
        .overlay(alignment: .topLeading) { dragOverlay }
        // The strip runs from the status item to the bottom of the screen, so
        // this is how much room the card actually has — measured rather than
        // assumed, because it is a different number on every display and on
        // every position of the menu-bar icon.
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { measured in
            if measured > 0, stripHeight != measured { stripHeight = measured }
        }
        .onReceive(NotificationCenter.default.publisher(for: .helmModuleOrderChanged)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .helmMenuBarStyleChanged)) { _ in
            showEditButton = AppSettings.showPanelEditButton
            showSettingsButton = AppSettings.showSettingsButton
            showQuitButton = AppSettings.showQuitButton
            tabLabels = AppSettings.tabLabelStyle
        }
        // Every opening, not only the first: the view is built once and stays
        // mounted between them, so `onAppear` fires exactly once in a session
        // and a transition would never play again.
        //
        // Two turns, deliberately. Setting the start state and animating to the
        // end in one update is one update — SwiftUI coalesces them and there is
        // nothing to interpolate from.
        .onReceive(NotificationCenter.default.publisher(for: .helmPanelDidShow)) { _ in
            // Back to the first tab. The comment on `activeTab` has always
            // said the panel is opened for a glance and must not answer a
            // question nobody asked — but this view is mounted once at launch,
            // so «the session» was the whole time the app had been running.
            activeTab = 0
            revealed = false
            // Everything else that used to run from `onAppear` and therefore
            // ran once for the life of the app.
            //
            // `reload` because a module switched on in Settings posts
            // `.helmModuleEnabled`, not `.helmModuleOrderChanged`: without this
            // its widget had no slot until the next launch, and the store's own
            // comment promises it appears the first time the panel is opened.
            // The two probes because a grant given — or taken back — while the
            // app was running was never noticed, so the notice at the top of
            // the panel outlived the thing it was reporting.
            reload()
            diskAccess = PermissionCheck.currentFullDiskAccess()
            accessibility = PermissionCheck.currentAccessibility()
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
            // Two different sentences. `order` excludes what was taken off a
            // tile, so a person who had emptied their panel was told no modules
            // were enabled — false, with nine running — and sent to Settings
            // when the way back is the pencil twelve points below. A tab made
            // with «+» landed in the same place, and it was worse: it got no
            // sentence at all, because the grid was simply empty.
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
                    .transition(.opacity)
                if editing { gallery(parts.byID) }
            }
    }

    private func emptyState(_ symbol: String, _ title: String, _ hint: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(HelmText.quiet)
            Text(title).font(HelmText.sectionHeading)
            Text(hint)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// What the grid may take: the strip, less the pinned bars, the card's own
    /// padding and the two gaps between the three blocks. Never less than one
    /// row, so a very short strip still shows something to scroll.
    private var availableForGrid: CGFloat {
        let strip = stripHeight > 0 ? stripHeight : PanelGrid.maximumHeight
        let ceiling = min(strip, PanelGrid.maximumHeight)
        // The pinned bars are not always there. Their last measurement is,
        // which would keep reserving room for a strip that is no longer drawn.
        //
        // Both of them. The mask went on the strip and not on the foot, so
        // switching the last footer button off left 38 pt reserved under a
        // footer that had stopped being drawn — and a grid that had exactly
        // fitted began to scroll. SwiftUI does report the collapse; the
        // writer's `guard measured > 0` throws that report away, which is
        // correct there and is why the reader has to do this.
        let pinned = (layout.showsTabBar || editing) ? topChrome : 0
        let foot = (editing || showSettingsButton || showQuitButton || showEditButton)
            ? footerHeight : 0
        return max(120, ceiling - pinned - foot - 24 - 16)
    }

    private func card(_ parts: Candidates, _ items: [Widget]) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            // Pinned: the strip, the setup bar and the footer. Only the grid
            // scrolls — the way out of a mode must not be something you have to
            // scroll to, and in edit mode every widget grows a frame and a pair
            // of corner controls, which is what pushed the footer off the
            // bottom of the screen.
            // Only when there is something pinned. An empty `VStack` has no
            // height, but the stack around it still puts its 8 pt gap after it
            // — so a panel with one tab and nothing being arranged opened with
            // 20 pt above its first widget where every other edge has 12.
            if layout.showsTabBar || editing {
                tabStrip
                    // In a transaction, like the grid's height. These two were
                    // the last raw writes left, and they are exactly the ones
                    // that change when the mode is entered — the strip appears,
                    // the edit bar appears — so the panel animated its middle
                    // and snapped its ends.
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { measured in
                        guard measured > 0, topChrome != measured else { return }
                        if topChrome == 0 { topChrome = measured }
                        else { withAnimation(HelmMotion.disclosure) { topChrome = measured } }
                    }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
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
                // Written **inside** a transaction, which is the whole fix.
                //
                // `onGeometryChange` hands its measurement over outside the one
                // that is running, so the card's height arrived unanimated
                // while the rows it measured were still sliding: the list
                // unfolded over 0.3 s and the panel reached its full height in
                // one frame. `.animation(_, value:)` on the frame does not
                // rescue it — measured against the real view, that variant is
                // indistinguishable from no animation at all, and only the
                // explicit transaction ramps. `DisclosureProbe` holds both.
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { measured in
                    guard measured > 0, gridHeight != measured else { return }
                    // The first measurement is not a change, it is the answer.
                    //
                    // Until it lands the scroll view has no height of its own
                    // and takes everything it is offered — the whole strip —
                    // so animating that first write plays the card collapsing
                    // from full height to its content while the card is pinned
                    // at the top. Opening the panel looked like the block
                    // unfolding from its middle in both directions.
                    if gridHeight == 0 { gridHeight = measured }
                    else { withAnimation(HelmMotion.disclosure) { gridHeight = measured } }
                }
            }
            // An explicit height, not a `maxHeight`. A `ScrollView`'s ideal
            // height is not its content's, so in a stack that is free to be
            // short it took a few hundred points and clipped the grid halfway
            // through a widget while the card had room to spare. This is the
            // smaller of what the grid needs and what the strip has left.
            .frame(height: gridHeight > 0 ? min(gridHeight, availableForGrid) : nil)
            .scrollIndicators(.automatic)
            // The way out sits with the other two ways out, at the foot of the
            // panel. It was pinned to the top, a hundred points from «Настройки»
            // and «Завершить» — three exits from the same card, two of them
            // together and one on its own at the other end.
            VStack(alignment: .leading, spacing: 8) {
                if editing { editBar }
                footer
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { measured in
                guard measured > 0, footerHeight != measured else { return }
                if footerHeight == 0 { footerHeight = measured }
                else { withAnimation(HelmMotion.disclosure) { footerHeight = measured } }
            }
        }
        .padding(12)
        .frame(width: helmPanelWidth)
        // A fade, and nothing else. macOS menus and menu-bar extras do not
        // grow, scale or slide into place — they are there, over a fade quick
        // enough that the fade is not the thing you notice. The scale from the
        // top edge that was here read as a web popover.
        .opacity(revealed ? 1 : 0)
        // No `maxHeight` here, and that is the point. `maxHeight` is greedy: it
        // takes the smaller of the maximum and whatever the parent proposes,
        // and the parent is a strip running to the bottom of the screen — so a
        // panel holding one widget drew a card 768 pt tall with the footer
        // floating in the middle of it.
        //
        // The ceiling is already kept where it belongs: the scroll view is the
        // one thing allowed to give way, and `availableForGrid` is what the
        // strip has left after the pinned bars. Everything else is its own
        // size, so the card is the sum of its parts.
        .alert(AppStr.renameSection, isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField(AppStr.tabLabel, text: $draftName)
            Button(AppStr.done) {
                if let id = renaming { apply(layout.renamingTab(id, to: draftName)) }
                renaming = nil
            }
            Button(AppStr.cancel, role: .cancel) { renaming = nil }
        }
        .onAppear {
            reload()
            diskAccess = PermissionCheck.currentFullDiskAccess()
            accessibility = PermissionCheck.currentAccessibility()
        }
        // Liquid Glass, and no border of our own: glass supplies its specular
        // edge, and a hand-drawn hairline on top of it doubles the line. 26 pt
        // rather than 20 so the radius is concentric with the 14 pt tile cards
        // inside at 12 pt of padding — that is what makes them read as nested
        // rather than merely stacked.
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .containerShape(.rect(cornerRadius: 26))
        // Centred in a strip that is wider than the card, so the glass has
        // somewhere to cast. This must come after the glass: applied before
        // it, the effect painted the whole strip and the card came out 56 pt
        // wider than the tiles inside it.
        .frame(maxWidth: .infinity)
        // Pin the card to the TOP of the hosting bounds: while window and content
        // sizes momentarily disagree, the slack stays at the transparent bottom
        // instead of the default centering, which read as the card dropping.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
