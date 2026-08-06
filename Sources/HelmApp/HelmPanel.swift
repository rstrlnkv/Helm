import AppKit
import SwiftUI
import HelmRuntime
import HelmUI

/// Borderless, non-activating panel shown below the status item; stacks each
/// enabled module's panel tile (settings/quit live in the right-click menu).
/// Borderless panels can't normally become key; this one must, so its SwiftUI
/// controls (toggles, text fields) accept input.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Escape closes it, as every menu and popover on the machine does.
    ///
    /// The panel took key focus so its controls would accept input, and then
    /// answered only the mouse: clicking outside dismissed it, Escape did
    /// nothing at all. Somebody who opened it from the keyboard shortcut had no
    /// way to close it from the keyboard.
    ///
    /// `cancelOperation` rather than a key handler: it is what AppKit sends for
    /// Escape *and* for ⌘. , and it arrives after the responder chain has had
    /// its say — so a text field mid-edit or a `HelmHotkeyRecorder` capturing a
    /// shortcut still gets to take the key first. It goes out as the same
    /// notification the click-through path posts, so there is one way to close.
    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .helmPanelDismissRequested, object: nil)
    }
}

/// One width for the strip window and the card content inside it.
///
/// It was briefly a setting, on the argument that the column count follows from
/// it. It does — 480 buys a third column — and that is not a reason to ask:
/// three columns of 147 pt in a menu-bar panel is a grid nobody wants and a
/// question everybody has to answer once.
///
/// **320, not the 300 it shipped at.** `PanelGrid.minimumTile` is 144 and the
/// prose under it argues the floor properly — «below it a button already costs
/// the figure it sits under» — and then 300 pt bought two columns of 134. Every
/// 1×1 in the app was 10 pt under a floor the app itself had written down. 320
/// is the width the mockups always used, and it makes the rule true: two tiles
/// of exactly 144.
private let helmPanelWidth: CGFloat = 320
/// Room on each side of the card for the glass to cast into.
///
/// A window shadow is drawn by the window server *outside* the frame, so the
/// strip could be exactly as wide as the card. Glass draws its shading inside
/// the view, so with the two the same width the card's own shadow was cut off
/// flat at the left and right edges. The band is transparent and behaves like
/// the rest of the strip below the card: a click there dismisses the panel.
private let helmPanelShadowMargin: CGFloat = 28

@MainActor final class HelmPanel: NSObject {
    private let panel: NSPanel
    private let hosting: NSHostingView<HelmPanelContent>
    private var dismissMonitor: Any?
    private var dismissObserver: NSObjectProtocol?
    private var statusButtonScreenFrame: NSRect = .zero
    /// Screen the panel was opened on; clamping target for repositioning.
    private var anchorScreen: NSScreen?

    init(host: ModuleHost) {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        // NOT hidesOnDeactivate: the app is usually inactive when the panel is
        // shown from the menu bar, which would hide it instantly. We dismiss it
        // ourselves via an outside-click monitor.
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The window draws no shadow: Liquid Glass carries its own, and the two
        // disagree about what the silhouette is. With `.regularMaterial` the
        // window's shadow was derived from the opaque part — the card — and
        // looked right. Glass paints its backdrop across the hosting view,
        // which is a transparent strip running from the status item to the
        // bottom of the screen, so AppKit started shading *that*: a hairline
        // tracing the shadow instead of the card's edge.
        panel.hasShadow = false
        panel.isMovable = false
        self.panel = panel

        // Sized ONCE per open (a transparent strip from the status item to the
        // screen bottom) and never moved while visible: moving a transparent
        // layer-backed window drags its composited surface ahead of the SwiftUI
        // redraw, which is what made an animating card look like it slid. The
        // card is top-pinned and animates entirely inside the static window.
        // A plain NSHostingView is used deliberately — a custom hitTest here
        // previously swallowed every click.
        let hosting = NSHostingView(rootView: HelmPanelContent(host: host))
        hosting.sizingOptions = []
        self.hosting = hosting
        panel.contentView = hosting
        super.init()
        dismissObserver = NotificationCenter.default.addObserver(
            forName: .helmPanelDismissRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo statusButton: NSStatusBarButton) {
        if panel.isVisible {
            hide()
            return
        }
        guard let buttonWindow = statusButton.window else { return }
        statusButtonScreenFrame = buttonWindow.convertToScreen(statusButton.frame)
        anchorScreen = buttonWindow.screen ?? NSScreen.main
        reframe()
        panel.orderFrontRegardless()
        // Key focus (no app activation) is what makes SwiftUI animations tick.
        panel.makeKey()
        NotificationCenter.default.post(name: .helmPanelDidShow, object: nil)
        installDismissMonitor()
    }

    /// Whether the panel is on screen, for a caller that wants it open rather
    /// than toggled.
    var isShown: Bool { panel.isVisible }

    private func hide() {
        removeDismissMonitor()
        panel.orderOut(nil)
    }

    /// The strip, sized and clamped to the screen the panel was opened on.
    ///
    /// Pulled out of `toggle` when the width became a setting: changing it
    /// while the panel is open has to move the window, and re-deriving the
    /// frame from the anchor is the only way that stays centred on the status
    /// item rather than growing off one edge.
    private func reframe() {
        let visible = anchorScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        let width = helmPanelWidth + helmPanelShadowMargin * 2
        var x = statusButtonScreenFrame.midX - width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - width - margin)
        let top = statusButtonScreenFrame.minY - 4
        let bottom = visible.minY + margin
        panel.setFrame(NSRect(x: x, y: bottom, width: width, height: max(top - bottom, 120)),
                       display: true, animate: false)
    }



    /// Close the panel when the user clicks outside it (but not on the status
    /// item itself — that click re-toggles through the normal path).
    private func installDismissMonitor() {
        removeDismissMonitor()
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            if self.statusButtonScreenFrame.contains(loc) { return }
            self.hide()
        }
    }

    private func removeDismissMonitor() {
        if let dismissMonitor {
            NSEvent.removeMonitor(dismissMonitor)
            self.dismissMonitor = nil
        }
    }
}

extension Notification.Name {
    /// Posted when the transparent area under the card is clicked.
    static let helmPanelDismissRequested = Notification.Name("helmPanelDismissRequested")
    /// Posted by the icon's menu: open the panel and arrange it.
    static let helmPanelEditRequested = Notification.Name("helmPanelEditRequested")
    /// Posted when the panel is put on screen. The view is built once and
    /// stays, so there is no `onAppear` for a second opening — this is how it
    /// knows to play its entrance.
    static let helmPanelDidShow = Notification.Name("helmPanelDidShow")
}

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
    /// Bumped when the arrangement changes so the panel rebuilds its rows.
    @State private var orderTick = 0

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
        case utilities
    }

    /// One widget, at the size it ended up with.
    private struct Widget: Identifiable {
        let id: String
        let content: WidgetContent
        let size: PanelWidgetSize
        /// Arrives by itself and cannot be taken off — the permissions notice
        /// is the only one, and it leaves when the grant is given.
        var pinned = false
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
    private var candidates: (byID: [String: ModuleHost.Live], order: [String],
                             utilities: [ModuleHost.Live], choosable: [ModuleHost.Live]) {
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
        return (byID, order, utilities, choosable)
    }

    /// The stored arrangement decides what is drawn and in what order; the live
    /// modules decide what *can* be drawn.
    /// Never stored: it arrives while a grant is missing and leaves with it,
    /// so putting it in the layout would mean writing a row that has to be
    /// deleted again the moment somebody presses Grant — and deciding, on
    /// every read, whether an absent one was removed or never added.
    private var permissionsWidget: Widget? {
        let missing = PermissionSummary.withheld(accessibility: accessibility, fullDisk: diskAccess)
        guard !missing.isEmpty else { return nil }
        return Widget(id: Self.permissionsWidget,
                      content: .module(AnyView(PermissionsWidget(
                          withheld: missing, modules: PermissionSummary.affected(by: missing)))),
                      size: .wide, pinned: true)
    }

    private var tabIndex: Int { min(max(0, activeTab), max(0, layout.tabs.count - 1)) }

    private func widgets(_ byID: [String: ModuleHost.Live]) -> [Widget] {
        let slots = layout.tabs.indices.contains(tabIndex) ? layout.tabs[tabIndex].widgets : []
        let placed: [Widget] = slots.compactMap { slot in
            if slot.widget == Self.utilitiesWidget {
                // One size. «How much room does the list of everything else
                // take» is not a question with three answers.
                return Widget(id: slot.widget, content: .utilities, size: .tall)
            }
            guard let live = byID[slot.widget] else {
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
            return Widget(id: slot.widget, content: .module(view), size: size)
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
        // Keyed by the widgets in the row, not by the row's position.
        //
        // With `id: \.offset` a reorder changed what row 2 *contained*, and to
        // SwiftUI that is a different row 2 — it replaced the subtree instead of
        // moving anything, so no amount of animation on the outside could make
        // a tile travel. This is the fix the two previous attempts were missing.
        ForEach(rows, id: \.self) { row in
            HStack(alignment: .top, spacing: PanelGrid.gap) {
                // By the widget, not by the index. An index is a *position*,
                // and a reorder changes what position holds what — so every
                // reorder rebuilt the cells, resetting any state a tile kept
                // and killing any gesture that lived on one mid-drag. That is
                // how a carried widget could be left hanging in the air: the
                // gesture's view died under it and `onEnded` never came.
                ForEach(row.map { items[$0] }) { item in
                    cell(item, among: items)
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
    private func cell(_ widget: Widget, among items: [Widget]) -> some View {
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
                                 sizes: offeredSizes(widget.id),
                                 lifted: dragging?.id == widget.id,
                                 // The drawer's rows must stay pressable while
                                 // its pencil is choosing them; everything else
                                 // is arrangement, not use.
                                 shielded: editing && !(widget.id == Self.utilitiesWidget
                                                        && choosingUtilities),

                                 // The drawer chooses contents, not proportions.
                                 choose: widget.id == Self.utilitiesWidget
                                     ? { choosingUtilities.toggle() } : nil,
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
                                 remove: { apply(layout.removing(widget.id)) },
                                 move: { offset in nudge(widget.id, by: offset, among: items) }))
            // Its rectangle, so the container's drag knows what is where —
            // both for picking a tile up and for knowing what the pointer is
            // over.
            .onGeometryChange(for: CGRect.self,
                              of: { $0.frame(in: .named(Self.gridSpace)) }) { rect in
                if frames[widget.id] != rect { frames[widget.id] = rect }
            }
        }
    }

    /// The drawer, at the one size it has.
    private var utilitiesWidget: some View {
        let parts = candidates
        return UtilitiesSection(modules: choosingUtilities ? parts.choosable : parts.utilities,
                                expanded: $utilitiesExpanded,
                                editing: editing,
                                choosing: choosingUtilities,
                                isOn: { !layout.isHidden($0) },
                                toggle: { id in
                                    apply(layout.isHidden(id) ? layout.restoring(id)
                                                              : layout.hiding(id))
                                },
                                )
    }

    /// The one branch that keeps a concrete type — see `WidgetContent`.
    @ViewBuilder
    private func body(of widget: Widget) -> some View {
        Group {
            switch widget.content {
            case .module(let view): view
            case .utilities: utilitiesWidget
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
    private func gridDrag(items: [Widget]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.gridSpace))
            .onChanged { value in
                if dragging == nil {
                    guard let hit = frames.first(where: {
                              $0.key != Self.permissionsWidget
                                  && $0.value.contains(value.startLocation)
                          })?.key,
                          let widget = items.first(where: { $0.id == hit }),
                          let frame = frames[hit]
                    else { return }
                    // The frames are measured outside `EditChrome`, which pads
                    // every tile by 4 pt in this mode — so the raw frame is the
                    // tile plus 8 pt each way. The overlay draws the *content*,
                    // and drawing it at the padded size inflated the carried
                    // tile just enough to be visibly bigger than the slot it
                    // lands in, with a snap down at the handover.
                    let content = frame.insetBy(dx: Self.chromeInset, dy: Self.chromeInset)
                    dragSize = content.size
                    grabOffset = CGSize(width: value.startLocation.x - content.minX,
                                        height: value.startLocation.y - content.minY)
                    dropping = false
                    withAnimation(HelmMotion.reorder) { dragging = widget }
                }
                guard let carried = dragging else { return }
                dragLocation = value.location

                // The slot under the pointer, if it is a different one —
                // checked against live frames, so the boundary between two
                // tiles is exactly where the neighbour starts to move.
                guard let over = frames.first(where: {
                          $0.key != carried.id && $0.key != Self.permissionsWidget
                              && $0.value.contains(value.location)
                      })?.key,
                      let overFrame = frames[over],
                      let target = layout.placement(of: over),
                      let here = layout.placement(of: carried.id),
                      here.tab != target.tab || here.index != target.index else { return }

                // Past the middle, not merely inside. Containment alone
                // oscillates against a tall neighbour: entering its top edge
                // swaps, the swap puts the pointer in its *bottom* half, which
                // reads as entered again — and the utilities list bounced in
                // place under a slowly moving pointer. Requiring the centre to
                // be crossed, on the axis the move is happening along, is the
                // hysteresis: after a swap the pointer is on the near side of
                // the centre, and nothing fires until it truly travels.
                let slot = frames[carried.id] ?? overFrame
                let sameRow = abs(overFrame.midY - slot.midY) < 4
                let crossed = sameRow
                    ? (overFrame.midX > slot.midX ? value.location.x > overFrame.midX
                                                  : value.location.x < overFrame.midX)
                    : (overFrame.midY > slot.midY ? value.location.y > overFrame.midY
                                                  : value.location.y < overFrame.midY)
                guard crossed else { return }
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
                let home = frames[carried.id]?.insetBy(dx: Self.chromeInset, dy: Self.chromeInset)
                // `.removed`, not `.logicallyComplete`: the logical end comes
                // before the spring's visible tail, so the handover used to
                // happen while the overlay was still settling — a cut in the
                // last frame of the landing.
                withAnimation(HelmMotion.reorder, completionCriteria: .removed) {
                    dropping = true
                    if let home {
                        dragLocation = CGPoint(x: home.minX + grabOffset.width,
                                               y: home.minY + grabOffset.height)
                    }
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

    private func offeredSizes(_ id: String) -> [PanelWidgetSize] {
        guard let live = candidates.byID[id] else { return [] }
        let offered = live.descriptor.panelWidgetSizes(live.vm)
        return PanelWidgetSize.allCases.filter { offered.contains($0) }
    }


    /// Keyboard reordering. The panel is reachable from the keyboard and the
    /// edit mode must not be the one place that is not.
    private func nudge(_ id: String, by offset: Int, among items: [Widget]) {
        guard let at = layout.placement(of: id) else { return }
        apply(layout.moving(id, toTab: at.tab, at: max(0, at.index + offset)))
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
                            apply(layout.removingTab(tab.id))
                            activeTab = min(tabIndex, max(0, layout.tabs.count - 1))
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
                        apply(layout.addingTab(id: "tab.\(n)"))
                        activeTab = layout.tabs.count - 1
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
            apply(layout.adding(id, toTab: tabIndex))
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
        VStack(spacing: 0) {
            card
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
            orderTick &+= 1
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
    private func scrollable(_ parts: (byID: [String: ModuleHost.Live], order: [String],
                                      utilities: [ModuleHost.Live], choosable: [ModuleHost.Live]),
                            _ items: [Widget]) -> some View {
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
                           AppStr.nothingOnThisTabHint)
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
        let pinned = (layout.showsTabBar || editing) ? topChrome : 0
        return max(120, ceiling - pinned - footerHeight - 24 - 16)
    }

    private var card: some View {
        let parts = candidates
        let items = widgets(parts.byID)
        return VStack(alignment: .leading, spacing: 8) {

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

/// What a widget grows while the panel is being arranged: a dashed frame, a
/// minus at the top left, and its proportions at the top right.
///
/// **Both float at the corners, half outside the tile.** That is where macOS
/// has put «remove» since the first jiggling icon, and the reason it works is
/// the reason it is not an overlay *on* the content: the corner of a card is
/// the one place a module never draws anything, so a control parked there
/// costs nothing. An earlier version put the chips inside the tile's
/// bottom-right corner instead and they landed on the VPN switch, Keep Awake's
/// «⋯» and the Disk widget's used-of-total.
///
/// **The size control is one chip until you point at it.** Three chips on
/// every tile is a row of controls competing with the tile for attention, on a
/// panel whose whole job is to be read at a glance; one chip says what the size
/// *is*, which is the part worth showing all the time. It opens on hover and
/// on focus — hover alone would put a control on the panel that a keyboard
/// cannot reach.
private struct EditChrome: ViewModifier {
    let active: Bool
    let widget: String
    let size: PanelWidgetSize
    let sizes: [PanelWidgetSize]
    /// This tile is the one being carried, so it is a slot: no content, and no
    /// controls hanging off a corner that has nothing behind it.
    let lifted: Bool
    /// The mode is arrangement, not use: a clear layer over the tile's own
    /// controls, so a drag can start anywhere on it — a toggle that still
    /// worked would claim the mouse-down and make half of every tile
    /// ungrabbable. The chrome sits above the shield and stays pressable.
    let shielded: Bool

    /// Non-nil for a widget whose corner control chooses something other than a
    /// size — the drawer, which chooses its rows.
    let choose: (() -> Void)?
    let choosing: Bool
    let resize: (PanelWidgetSize) -> Void
    let remove: () -> Void
    let move: (Int) -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    private var open: Bool { hovering || focused }

    func body(content: Content) -> some View {
        // **One branch, whatever the mode.** This used to be `if !active {
        // content } else { content.decorated }`, and the two branches are two
        // identities to SwiftUI — entering the edit mode tore every tile down
        // and rebuilt it, so there was nothing to interpolate and the whole
        // grid snapped. That was the judder that survived four animation
        // fixes: it was never the animation, it was the identity.
        content
            // The slot of a tile that is being carried: the content steps
            // aside, a quiet well marks the place, and the overlay above the
            // grid is the one full-weight copy under the pointer.
            .opacity(lifted ? 0 : 1)
            .background {
                if lifted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(HelmSurface.wellFill)
                        .transition(.opacity)
                }
            }
            // The slot dims on its own clock, slower than the pickup. The lift
            // is on `reorder` — a quarter-second spring, right for a tile
            // answering a hand — but the same curve on the fade read as the
            // content being switched off. What empties out behind your hand is
            // background, and background takes its time. Scoped here so only
            // the fade and the well take it; the tile's geometry stays on the
            // transaction that moves it.
            .animation(HelmMotion.disclosure, value: lifted)
            .overlay {
                if shielded {
                    Color.clear.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .overlay(alignment: .topLeading) {
                if active, !lifted {
                    Button {
                        withAnimation(HelmMotion.disclosure) { remove() }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(HelmSignal.danger))
                            .shadow(radius: 1, y: 0.5)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -4, y: -4)
                    .accessibilityLabel(AppStr.removeWidget)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                Group {
                    if !active || lifted {
                        EmptyView()
                    } else if let choose {
                        Button(action: choose) {
                            Image(systemName: choosing ? "checkmark" : "pencil")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(choosing ? Color.white : HelmText.quiet)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Capsule().fill(choosing ? AnyShapeStyle(Color.accentColor)
                                                           : AnyShapeStyle(.regularMaterial)))
                                .overlay(Capsule().strokeBorder(HelmSurface.hairline))
                        }
                        .buttonStyle(.plain)
                        .help(AppStr.chooseUtilities)
                        .accessibilityLabel(AppStr.chooseUtilities)
                    } else {
                        sizeControl
                    }
                }
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
            // The room the corner controls overhang by, exactly: the grid
            // lives in a `ScrollView`, which clips at its own bounds. Animated
            // by the mode's own transaction, since it is part of what the mode
            // changes.
            .padding(active ? 4 : 0)
            // Movable by arrow keys, so the arrangement is not the one part of
            // the panel a keyboard cannot reach. No system ring: it is drawn
            // round the frame and arrived as a hard rectangle over glass.
            .focusable(active)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                guard active else { return }
                switch direction {
                case .left, .up: move(-1)
                case .right, .down: move(1)
                default: break
                }
            }
    }

    /// Grows leftwards from the corner it is anchored to, which is what a
    /// trailing-aligned stack does by itself.
    private var sizeControl: some View {
        HStack(spacing: 2) {
            ForEach(open ? sizes : [size], id: \.self) { option in
                Button {
                    // Shut on the way out, and say so *before* the resize.
                    //
                    // The tile changes shape under the pointer, so the control
                    // slides out from under it and `onHover(false)` never
                    // arrives — the pill stayed open, with the chip it had just
                    // chosen lit blue, until something else moved. Clicking also
                    // leaves the button focused, and focus is the other half of
                    // «open».
                    hovering = false
                    focused = false
                    resize(option)
                } label: {
                    // The accent marks *which of the three*, so it appears
                    // only when there are three. Closed, the chip is one label
                    // saying what the size is, and a blue pill on every tile
                    // would be the loudest thing in a panel meant to be read
                    // at a glance.
                    Text(option.label)
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(open && option == size ? Color.white
                                         : HelmText.quiet)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        // A capsule inside a capsule. The container is one, and
                        // a 4 pt rounded rectangle inside it is concentric with
                        // nothing — the corner of the chip cut across the curve
                        // of the pill it sat in. A capsule's radius is half its
                        // own height, so the two are concentric whatever the
                        // type size does to them.
                        .background(Capsule()
                            .fill(open && option == size ? Color.accentColor : .clear))
                }
                .buttonStyle(.plain)
                .help(option.label)
            }
        }
        .padding(2)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(HelmSurface.hairline))
        .focusable()
        .focused($focused)
        // The system ring is drawn round the view's *frame*, and this view is a
        // capsule inside one — so it came out as a rounded rectangle floating
        // around a pill, at a different radius and a different size.
        //
        // Turned off rather than reshaped, because this control already shows
        // its focus by doing something better than a ring: it opens. Three
        // chips where there was one is a clearer «you are here» than a line
        // round the outside, and it is the same signal a pointer gets.
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(HelmMotion.interface, value: open)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppStr.widgetSize)
    }
}

/// Reordering by dragging. Off unless the panel is being arranged: a tile that
/// lifts under a pointer that meant to press a button is an arrangement nobody
/// asked to change, and there is no undo here.
/// One collapsed row listing the modules whose UI lives in Settings. Expanding
/// reveals compact rows; clicking one opens Settings on that module.
struct UtilitiesSection: View {
    let modules: [ModuleHost.Live]
    @Binding var expanded: Bool
    /// The drawer is arranged like everything else in the panel: while the mode
    /// is on, every row offers a way out. It is also held open — a list you
    /// have to disclose before you can edit it is a list nobody edits.
    let editing: Bool
    /// The pencil is pressed: every row is a choice rather than a shortcut.
    let choosing: Bool
    let isOn: (String) -> Bool
    let toggle: (String) -> Void
    private var open: Bool { expanded || editing }
    /// Natural height of the rows, measured so the disclosure animates between
    /// 0 and a concrete value.
    @State private var rowsHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(HelmMotion.disclosure) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HelmText.quiet)
                    Text(AppStr.utilities).font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(modules.count)").font(.caption).foregroundStyle(HelmText.faint)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HelmText.faint)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The count is on screen and was being thrown away: a bare
            // `.accessibilityLabel` *replaces* the label SwiftUI synthesizes
            // from the row, so "Utilities 3 ›" was read as "Utilities". The
            // count goes back as the value, where a number belongs, and the
            // open/closed state with it — a disclosure that will not say
            // whether it is open answers its own button press with silence.
            .accessibilityLabel(AppStr.utilities)
            .accessibilityValue("\(Count(modules.count)), \(HelmA11y.expanded(open))")

            // Measured height rather than `if expanded`: with the rows removed
            // from the hierarchy the card's background collapsed instantly
            // while the disappearing rows kept drawing over whatever sat
            // below. Keeping them mounted and clipping to an animated height
            // means the block's edge always contains its content — the same
            // pattern Keep Awake's inline block uses.
            VStack(spacing: 2) {
                ForEach(modules, id: \.descriptor.idRaw) { live in
                    HStack(spacing: 6) {
                        utilityRow(live)
                        if choosing {
                            Button { toggle(live.descriptor.idRaw) } label: {
                                Image(systemName: isOn(live.descriptor.idRaw)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(isOn(live.descriptor.idRaw)
                                                     ? Color.accentColor : HelmText.faint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                if height > 0 { rowsHeight = height }
            }
            .frame(height: open ? rowsHeight : 0, alignment: .top)
            // Height + clipping only: fading would isolate these rows in their
            // own layer and their materials would stop blending with the card.
            .clipped()
            .allowsHitTesting(open)
        // `.clipped()` hides it from the eye, not from the accessibility tree.
        .accessibilityHidden(!open)
        }
        .helmPanelCard()
    }

    private func utilityRow(_ live: ModuleHost.Live) -> some View {
        let meta = live.descriptor.moduleMetadata
        return Button {
            NotificationCenter.default.post(name: .helmOpenSettings, object: live.descriptor.idRaw)
        } label: {
            HStack(spacing: 8) {
                HelmIconPlate(symbol: meta.sfSymbol,
                              tint: live.descriptor.moduleTint.colour, size: 20)
                // The short name, as the sidebar asks for: this column is
                // fixed and «Объекты входа и расширения» is cut mid-word in it.
                Text(meta.shortName).font(.callout).lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(HelmText.faint)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The notice that arrives by itself: macOS is withholding something, and
/// these modules are the ones it reaches.
///
/// Not removable, and it is not in the layout at all. Storing it would mean
/// writing a row that has to be deleted the moment somebody presses Grant —
/// and deciding, on every read, whether an absent one was taken off or never
/// added. It is a fact about the machine, so it is computed from the machine.
private struct PermissionsWidget: View {
    let withheld: [PermissionNeed]
    let modules: Int

    var body: some View {
        HelmWidgetBody {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(HelmSignal.warning)
                Text(AppStr.permissionsWithheld(count: withheld.count, modules: modules))
                    .font(HelmText.rowDetail)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                // One withheld grant has one place to go, so go there. Several
                // do not, and a button that picks one of them silently is a
                // button that lies about what it opened.
                if withheld.count == 1, let only = withheld.first {
                    Button(AppStr.grant) { only.openSettings() }
                        .controlSize(.small)
                } else {
                    Button(AppStr.show) {
                        NotificationCenter.default.post(name: .helmOpenSettings,
                                                        object: SettingsWindow.settingsPage)
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

/// The tile of a module that is switched off.
///
/// It keeps its place: dropping it would take the arrangement apart and leave
/// nobody able to say where the block went, and switching a module off is not
/// a request to rearrange the panel. The plate is drawn inactive, and the one
/// button is the way back.
private struct DisabledModuleWidget: View {
    let descriptor: any ModuleDescriptor

    var body: some View {
        HelmWidgetBody {
            HStack(spacing: 8) {
                HelmIconPlate(symbol: descriptor.moduleMetadata.sfSymbol,
                              tint: descriptor.moduleTint.colour, size: 18, active: false)
                Text(descriptor.moduleMetadata.shortName)
                    .font(HelmText.rowTitle.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            Text(AppStr.moduleIsOff)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
            Button(AppStr.turnOn) {
                ModuleHost.shared.setEnabled(descriptor, true)
                NotificationCenter.default.post(name: .helmModuleOrderChanged, object: nil)
            }
            .controlSize(.small)
        }
    }
}
