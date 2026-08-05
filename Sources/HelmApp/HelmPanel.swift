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
/// Chosen in the panel's own setup rather than fixed, because the column count
/// follows from it: 300 and 400 both give two columns and 480 gives three.
@MainActor private var helmPanelWidth: CGFloat { AppSettings.panelWidth }
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
        observeWidth()
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
        installDismissMonitor()
    }

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
    /// Kept for the lifetime of the panel: the width can change while it is
    /// open, from its own setup bar.
    private func observeWidth() {
        NotificationCenter.default.addObserver(forName: .helmPanelWidthChanged,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.reframe()
            }
        }
    }

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
    /// Posted when the panel's width changes, so the window follows the card.
    static let helmPanelWidthChanged = Notification.Name("helmPanelWidthChanged")
}

/// Internal rather than private so a test can render it: the panel is a
/// menu-bar window over Liquid Glass, and there is no other way to look at it
/// without a screenshot of somebody's screen.
struct HelmPanelContent: View {
    @ObservedObject var host: ModuleHost
    @State private var utilitiesExpanded = false
    /// The panel is being arranged rather than read.
    @State private var editing = false
    @State private var layout = PanelLayout(tabs: [])
    /// The one refusal the layout makes, shown where the attempt was made.
    @State private var refusal: String?
    @State private var width = AppSettings.panelWidth
    /// Which tab is being looked at. Session state, not stored: the panel is
    /// opened for a glance, and opening it on the tab somebody happened to
    /// leave last week is a panel that answers a question nobody asked.
    @State private var activeTab = 0
    @State private var renaming: String?
    @State private var draftName = ""
    @State private var diskAccess: PermissionState = .granted
    @State private var accessibility: PermissionState = .granted
    /// Bumped when the arrangement changes so the panel rebuilds its rows.
    @State private var orderTick = 0

    /// One widget, at the size it ended up with.
    private struct Widget: Identifiable {
        let id: String
        let view: AnyView
        let size: PanelWidgetSize
        /// Arrives by itself and cannot be taken off — the permissions notice
        /// is the only one, and it leaves when the grant is given.
        var pinned = false
    }

    /// The one widget that belongs to no module. This is why `Slot.widget` is
    /// an id rather than a module id.
    static let permissionsWidget = "helm.permissions"

    // MARK: - What the panel can draw right now

    /// Modules that offer a widget, and the ones whose UI lives in Settings.
    /// One pass — building a widget builds a view, so each module is asked once.
    private var candidates: (byID: [String: ModuleHost.Live], order: [String],
                             utilities: [ModuleHost.Live]) {
        var byID: [String: ModuleHost.Live] = [:]
        var order: [String] = []
        var utilities: [ModuleHost.Live] = []
        for live in host.enabledModules {
            guard let contribution = live.descriptor.menuBar(live.vm) else { continue }
            if contribution.isUtility { utilities.append(live); continue }
            byID[live.descriptor.idRaw] = live
            order.append(live.descriptor.idRaw)
        }
        return (byID, order, utilities)
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
                      view: AnyView(PermissionsWidget(withheld: missing,
                                                      modules: PermissionSummary.affected(by: missing))),
                      size: .wide, pinned: true)
    }

    private var tabIndex: Int { min(max(0, activeTab), max(0, layout.tabs.count - 1)) }

    private func widgets(_ byID: [String: ModuleHost.Live]) -> [Widget] {
        let slots = layout.tabs.indices.contains(tabIndex) ? layout.tabs[tabIndex].widgets : []
        let placed: [Widget] = slots.compactMap { slot in
            guard let live = byID[slot.widget] else {
                // A module that is switched off keeps its place and says so.
                // Dropping the tile would take the arrangement apart and leave
                // nobody able to say where the block went — and switching a
                // module off is not a request to rearrange the panel.
                guard let descriptor = ModuleRegistry.all.first(where: { $0.idRaw == slot.widget }),
                      !ModuleHost.shared.isEnabled(descriptor) else { return nil }
                return Widget(id: slot.widget,
                              view: AnyView(DisabledModuleWidget(descriptor: descriptor)),
                              size: slot.size)
            }
            let offered = live.descriptor.panelWidgetSizes(live.vm)
            guard let size = PanelGrid.resolve(slot.size, offered: offered),
                  let view = live.descriptor.panelWidget(size, live.vm) else { return nil }
            return Widget(id: slot.widget, view: view, size: size)
        }
        // At the top, always. It is the only thing in the panel that is wrong
        // right now, and a notice somebody has to scroll to is a notice.
        return [permissionsWidget].compactMap { $0 } + placed
    }

    private func reload() {
        layout = PanelLayoutStore.read(from: AppSettings.store, offered: candidates.order)
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
        let columns = PanelGrid.columns(for: width)
        let rows = PanelGrid.rows(sizes: items.map(\.size), columns: columns)
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            HStack(alignment: .top, spacing: PanelGrid.gap) {
                ForEach(row, id: \.self) { index in
                    cell(items[index], among: items)
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
            widget.view
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    if editing {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(HelmText.quiet))
                            .offset(x: -6, y: -6)
                            .help(AppStr.permissionsWidgetPinned)
                    }
                }
        } else {
        widget.view
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .modifier(EditChrome(active: editing, widget: widget.id, size: widget.size,
                                 sizes: offeredSizes(widget.id),
                                 refused: { layout.refusal(growing: widget.id, to: $0) != nil },
                                 resize: { size in
                                     if let why = layout.refusal(growing: widget.id, to: size) {
                                         refusal = message(for: why)
                                     } else {
                                         refusal = nil
                                         apply(layout.resizing(widget.id, to: size))
                                     }
                                 },
                                 remove: { apply(layout.removing(widget.id)) },
                                 move: { offset in nudge(widget.id, by: offset, among: items) }))
            .modifier(DragToReorder(active: editing, widget: widget.id) { dropped in
                guard let target = layout.placement(of: widget.id) else { return }
                apply(layout.moving(dropped, toTab: target.tab, at: target.index))
            })
        }
    }

    private func offeredSizes(_ id: String) -> [PanelWidgetSize] {
        guard let live = candidates.byID[id] else { return [] }
        let offered = live.descriptor.panelWidgetSizes(live.vm)
        return PanelWidgetSize.allCases.filter { offered.contains($0) }
    }

    private func message(for refusal: PanelLayout.Refusal) -> String {
        switch refusal {
        case .tallNeedsFullWidth: AppStr.tallNeedsFullWidth
        }
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
    @ViewBuilder
    private var tabStrip: some View {
        if layout.showsTabBar || editing {
            HStack(spacing: 4) {
                ForEach(Array(layout.tabs.enumerated()), id: \.element.id) { index, tab in
                    Button {
                        activeTab = index
                    } label: {
                        Text(AppStr.tabTitle(tab))
                            .font(HelmText.rowDetail.weight(index == tabIndex ? .semibold : .regular))
                            .foregroundStyle(index == tabIndex ? Color.primary : HelmText.quiet)
                            .lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(index == tabIndex ? HelmSurface.wellFill : .clear))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(AppStr.renameSection) {
                            draftName = AppStr.tabTitle(tab)
                            renaming = tab.id
                        }
                        Button(AppStr.closeTab, role: .destructive) {
                            apply(layout.removingTab(tab.id))
                            activeTab = min(tabIndex, max(0, layout.tabs.count - 1))
                        }
                        .disabled(layout.tabs.count == 1)
                    }
                    // ⌘1…⌘9, as every tabbed window on the machine.
                    .keyboardShortcut(index < 9 ? KeyEquivalent(Character("\(index + 1)")) : "0",
                                      modifiers: .command)
                }
                if editing {
                    Button {
                        let id = "tab.\(layout.tabs.count + 1).\(layout.allSlots.count)"
                        apply(layout.addingTab(id: id))
                        activeTab = layout.tabs.count - 1
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(HelmText.quiet)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStr.newTab)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The bar above the grid while the panel is being arranged.
    private var editBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(AppStr.panelSetup).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Button(AppStr.done) { editing = false; refusal = nil }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
            Picker(AppStr.panelWidth, selection: $width) {
                ForEach(AppSettings.panelWidths, id: \.self) { option in
                    Text("\(Int(option))").tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: width) { _, chosen in AppSettings.panelWidth = chosen }
            Text(AppStr.panelGeometry(columns: PanelGrid.columns(for: width),
                                      tile: Int(PanelGrid.tileWidth(for: width).rounded())))
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
            if let refusal {
                Text(refusal)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmSignal.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .helmPanelCard()
    }

    /// Everything not on this tab, as ghosts to press.
    @ViewBuilder
    private func gallery(_ byID: [String: ModuleHost.Live]) -> some View {
        let placed = Set(layout.allSlots.map(\.widget))   // not just this tab: a widget lives in one place
        let rest = candidates.order.filter { !placed.contains($0) }
        VStack(alignment: .leading, spacing: 6) {
            Text(AppStr.addWidget)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
            if rest.isEmpty {
                Text(AppStr.everythingIsHere)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.faint)
            } else {
                let columns = PanelGrid.columns(for: width)
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

    private func ghost(_ id: String, _ live: ModuleHost.Live?) -> some View {
        Button {
            apply(layout.adding(id, toTab: tabIndex))
        } label: {
            VStack(spacing: 4) {
                if let live {
                    HelmIconPlate(symbol: live.descriptor.moduleMetadata.sfSymbol,
                                  tint: live.descriptor.moduleTint.colour, size: 20)
                    Text(live.descriptor.moduleMetadata.shortName)
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
    private var footer: some View {
        HStack(spacing: 8) {
            footerButton(AppStr.settingsPane, "gearshape") {
                NotificationCenter.default.post(name: .helmOpenSettings, object: nil)
            }
            Spacer(minLength: 8)
            footerButton(editing ? AppStr.done : AppStr.configurePanel,
                         editing ? "checkmark" : "square.grid.2x2") {
                withAnimation(HelmMotion.interface) { editing.toggle() }
                refusal = nil
            }
            Spacer(minLength: 8)
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HelmText.quiet)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStr.quit)
        }
        .helmPanelCard()
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
        .onReceive(NotificationCenter.default.publisher(for: .helmModuleOrderChanged)) { _ in
            orderTick &+= 1
            reload()
        }
    }

    private var card: some View {
        let parts = candidates
        let items = widgets(parts.byID)
        return VStack(alignment: .leading, spacing: 8) {
            if parts.order.isEmpty && items.isEmpty && !editing {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 30))
                        .foregroundStyle(HelmText.quiet)
                    Text(AppStr.noModules).font(.headline)
                    Text(AppStr.noModulesHint)
                        .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                tabStrip
                if editing { editBar }
                grid(items)
                if editing { gallery(parts.byID) }
                if !parts.utilities.isEmpty {
                    UtilitiesSection(modules: parts.utilities, expanded: $utilitiesExpanded)
                }
            }
            footer
        }
        .padding(12)
        .frame(width: width)
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
        .onReceive(NotificationCenter.default.publisher(for: .helmPanelWidthChanged)) { _ in
            width = AppSettings.panelWidth
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
/// way out, and its three proportions.
///
/// A modifier rather than a wrapper view so the module's own tile keeps its
/// place in the grid — anything that puts a container around it changes how the
/// row measures.
private struct EditChrome: ViewModifier {
    let active: Bool
    let widget: String
    let size: PanelWidgetSize
    let sizes: [PanelWidgetSize]
    let refused: (PanelWidgetSize) -> Bool
    let resize: (PanelWidgetSize) -> Void
    let remove: () -> Void
    let move: (Int) -> Void

    func body(content: Content) -> some View {
        if !active { content } else {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
                        .strokeBorder(Color.accentColor,
                                      style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                .overlay(alignment: .topLeading) {
                    Button(action: remove) {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(HelmSignal.danger))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -6, y: -6)
                    .accessibilityLabel(AppStr.removeWidget)
                }
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 2) {
                        ForEach(sizes, id: \.self) { option in
                            Button { resize(option) } label: {
                                Text(option.label)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(option == size ? Color.white
                                                     : refused(option) ? HelmText.faint : HelmText.quiet)
                                    .padding(.horizontal, 5).padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(option == size ? Color.accentColor : HelmSurface.wellFill))
                            }
                            .buttonStyle(.plain)
                            .help(refused(option) ? AppStr.tallNeedsFullWidth : option.label)
                        }
                    }
                    .padding(4)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(AppStr.widgetSize)
                }
                // Focusable and movable by arrow keys, so the arrangement is
                // not the one part of the panel a keyboard cannot reach.
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
private struct UtilitiesSection: View {
    let modules: [ModuleHost.Live]
    @Binding var expanded: Bool
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
                        .rotationEffect(.degrees(expanded ? 90 : 0))
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
            .accessibilityValue("\(Count(modules.count)), \(HelmA11y.expanded(expanded))")

            // Measured height rather than `if expanded`: with the rows removed
            // from the hierarchy the card's background collapsed instantly
            // while the disappearing rows kept drawing over whatever sat
            // below. Keeping them mounted and clipping to an animated height
            // means the block's edge always contains its content — the same
            // pattern Keep Awake's inline block uses.
            VStack(spacing: 2) {
                ForEach(modules, id: \.descriptor.idRaw) { live in
                    utilityRow(live)
                }
            }
            .padding(.top, 8)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                if height > 0 { rowsHeight = height }
            }
            .frame(height: expanded ? rowsHeight : 0, alignment: .top)
            // Height + clipping only: fading would isolate these rows in their
            // own layer and their materials would stop blending with the card.
            .clipped()
            .allowsHitTesting(expanded)
        // `.clipped()` hides it from the eye, not from the accessibility tree.
        .accessibilityHidden(!expanded)
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
                Text(meta.name).font(.callout).lineLimit(1)
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
                        NotificationCenter.default.post(name: .helmOpenSettings, object: nil)
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
