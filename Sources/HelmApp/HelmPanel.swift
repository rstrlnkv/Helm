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
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            HStack(alignment: .top, spacing: PanelGrid.gap) {
                ForEach(row, id: \.self) { index in
                    cell(items[index], among: items)
                        // Two 1×1s in one row are one height. They were 95 and
                        // 89 — six points of ragged edge in a grid whose sizes
                        // are named after squares.
                        .frame(maxHeight: .infinity)
                        // Identity by widget, not by position. A cell keyed on
                        // its index in the row is a different cell the moment
                        // anything above it changes, and a different cell has
                        // different `@State` — which here is the measured
                        // height an open list animates between.
                        .id(items[index].id)
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
            body(of: widget)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                // A pin where the others have a minus, and it says why rather
                // than offering a control that would only refuse.
                .overlay(alignment: .topLeading) {
                    if editing {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            // An opaque fill, like the minus beside it.
                            // `HelmText.quiet` is a *text* token — 64% of the
                            // label colour — and a white glyph on it measured
                            // 1.46:1 over dark glass, which is a blank disc.
                            .background(Circle().fill(Color.gray))
                            .shadow(radius: 1, y: 0.5)
                            .offset(x: -5, y: -5)
                            .help(AppStr.permissionsWidgetPinned)
                            .accessibilityLabel(AppStr.permissionsWidgetPinned)
                    }
                }
                .padding(editing ? 4 : 0)
        } else {
        body(of: widget)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .modifier(EditChrome(active: editing, widget: widget.id, size: widget.size,
                                 sizes: offeredSizes(widget.id),

                                 // The drawer chooses contents, not proportions.
                                 choose: widget.id == Self.utilitiesWidget
                                     ? { choosingUtilities.toggle() } : nil,
                                 choosing: choosingUtilities,
                                 resize: { size in apply(layout.resizing(widget.id, to: size)) },
                                 remove: { apply(layout.removing(widget.id)) },
                                 move: { offset in nudge(widget.id, by: offset, among: items) }))
            .modifier(DragToReorder(active: editing, widget: widget.id) { dropped in
                guard let target = layout.placement(of: widget.id) else { return }
                apply(layout.moving(dropped, toTab: target.tab, at: target.index))
            })
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
        switch widget.content {
        case .module(let view): view
        case .utilities: utilitiesWidget
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
    private var editBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(AppStr.panelSetup).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Button(AppStr.done) { editing = false; choosingUtilities = false }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
            // Only once there is a strip to label.
            if layout.showsTabBar {
                Picker(AppStr.tabLabels, selection: $tabLabels) {
                    ForEach(TabLabelStyle.allCases, id: \.self) { style in
                        Text(AppStr.tabLabelStyle(style)).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: tabLabels) { _, chosen in AppSettings.tabLabelStyle = chosen }
            }
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
                    withAnimation(HelmMotion.interface) { editing = true }
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
            withAnimation(HelmMotion.interface) { editing = true }
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
                VStack(alignment: .leading, spacing: 8) {
                    tabStrip
                    if editing { editBar }
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { measured in
                    if measured > 0, topChrome != measured { topChrome = measured }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    scrollable(parts, items)
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
            footer
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { measured in
                    if measured > 0, footerHeight != measured { footerHeight = measured }
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
        if !active { content } else {
            content
                .overlay {
                    // 14, the tile's own radius: concentric, not merely near.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor,
                                      style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                .overlay(alignment: .topLeading) {
                    Button(action: remove) {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(HelmSignal.danger))
                            .shadow(radius: 1, y: 0.5)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -5, y: -5)
                    .accessibilityLabel(AppStr.removeWidget)
                }
                .overlay(alignment: .topTrailing) {
                    Group {
                        if let choose {
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
                    .offset(x: 5, y: -5)
                }
                // Room for the two of them to hang outside the card. 4 rather
                // than 7: at seven, every cell paid 14 pt and the edit mode
                // needed 751 pt of grid where the strip had 612 — the last tile
                // was cut through the middle with its dashed frame left open,
                // which reads as broken rather than as «there is more».
                .padding(4)
                .focusable()
                .onMoveCommand { direction in
                    switch direction {
                    case .left, .up: move(-1)
                    case .right, .down: move(1)
                    default: break
                    }
                }
        }
    }

    /// Grows leftwards from the corner it is anchored to, which is what a
    /// trailing-aligned stack does by itself.
    private var sizeControl: some View {
        HStack(spacing: 2) {
            ForEach(open ? sizes : [size], id: \.self) { option in
                Button { resize(option) } label: {
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
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
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
        .onHover { hovering = $0 }
        .animation(HelmMotion.interface, value: open)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppStr.widgetSize)
    }
}

/// Reordering by dragging. Off unless the panel is being arranged: a tile that
/// lifts under a pointer that meant to press a button is an arrangement nobody
/// asked to change, and there is no undo here.
private struct DragToReorder: ViewModifier {
    let active: Bool
    let widget: String
    let dropped: (String) -> Void

    func body(content: Content) -> some View {
        if !active { content } else {
            content
                .draggable(widget)
                .dropDestination(for: String.self) { items, _ in
                    guard let first = items.first, first != widget else { return false }
                    dropped(first)
                    return true
                }
        }
    }
}

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
