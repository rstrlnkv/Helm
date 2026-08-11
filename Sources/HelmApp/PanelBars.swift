import AppKit
import SwiftUI
import HelmRuntime
import HelmUI

// The rows of the card that are not tiles: the tab strip, the setup bar, the
// gallery of widgets no tab is holding, and the footer. Drawn by the card in
// `HelmPanel.swift`, which keeps the grid and everything the drag touches.
//
// Each takes what it needs and owns none of it. That is the rule the split was
// made under: the panel's `@State` is what the third drag architecture was
// bought with (ARCHITECTURE.md § Carrying a tile), so nothing here holds state
// the panel is steering by — a binding travels down, an action travels up.

/// The tabs, and it is the first row of the card **in both modes**.
///
/// In the mockups' first version it stood first when reading and second when
/// editing, so entering the mode moved every tab out from under the cursor that
/// had just pressed one.
struct PanelTabStrip: View {
    let layout: PanelLayout
    /// The tab being looked at, already clamped by the panel.
    let tabIndex: Int
    let editing: Bool
    let labels: TabLabelStyle
    /// The namespace the selection travels in. Handed down rather than declared
    /// here so it is the panel's, like the one the tiles travel in.
    let selection: Namespace.ID
    @Binding var activeTab: Int
    /// The tab whose glyph is being chosen, if any. A binding because the
    /// popover both reads it and puts it back.
    @Binding var pickingGlyph: String?
    /// Somebody asked to rename this tab, and here is what it is called now.
    /// An action rather than the two bindings it was: the strip only ever
    /// *writes* that pair, and what a rename means — an alert on the card —
    /// belongs to whoever owns the alert.
    let rename: (_ tab: String, _ current: String) -> Void
    let apply: (PanelLayout) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(layout.tabs.enumerated()), id: \.element.id) { index, tab in
                tabButton(index, tab)
            }
            if editing {
                Button {
                    // The lowest number nobody is using. Counting the tabs
                    // breaks the moment one in the middle is closed: three tabs
                    // minus the second is two, and the next new one would ask
                    // for an id the third already has.
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
        // ⌘1…⌘9, as every tabbed window on the machine — on buttons of their
        // own rather than on the tabs.
        //
        // A `keyboardShortcut` on a button decorates that button's *context
        // menu* as well, so every item of the tab's menu — Rename, Icon, Close
        // — was drawn with a «⌘2» it did not have and would not obey.
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

    private func tabButton(_ index: Int, _ tab: PanelLayout.Tab) -> some View {
        // Asked once. The label, the tooltip, the accessibility label and the
        // rename's draft are the same sentence, and it was built four times.
        let title = AppStr.tabTitle(tab, number: index + 1)
        return Button {
            // The strip and the grid move together: the selection slides while
            // the widgets under it cross-fade, on one transaction rather than
            // two.
            withAnimation(HelmMotion.interface) { activeTab = index }
        } label: {
            // The mockup's tab: 4 pt between glyph and text, 4×8 of padding, a
            // 10 pt corner, and 11 pt type that does **not** change weight when
            // selected.
            //
            // Weight was the first thing tried and it is the one thing a tab
            // cannot do: bold is wider than regular, so every tab in the strip
            // moved whenever another was picked. Selection is a background and
            // a colour.
            HStack(spacing: 4) {
                if labels.showsGlyph, let glyph = tab.glyph {
                    Image(systemName: glyph)
                        .font(.system(size: 13, weight: .medium))
                }
                if labels.showsText {
                    Text(title)
                        .font(HelmText.rowDetail)
                        .lineLimit(1)
                }
                // The way to a tab's own settings, on the tab that is open. The
                // context menu has the same three items; a chevron is what says
                // they are there.
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
                    // A material, not a 5% overlay. `wellFill` measured 1.23:1
                    // over the panel's glass and 1.04:1 in light — and the
                    // shadow under it was cast by a shape with 5% alpha, so it
                    // was ~0.6% black, which is nothing. A material composites
                    // against whatever is behind it, which is what a raised
                    // segment is.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        // One shape that moves between tabs rather than one
                        // appearing while another goes.
                        .matchedGeometryEffect(id: "tab.selection", in: selection)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        // Glyph-only tabs have nowhere to put their name; the pointer is where
        // it goes.
        .help(title)
        .accessibilityLabel(title)
        .contextMenu {
            Button(AppStr.renameSection) { rename(tab.id, title) }
            Button(AppStr.tabIcon) { pickingGlyph = tab.id }
            Button(AppStr.closeTab, role: .destructive) {
                // The token the tab buttons use. Bare, the content cut while
                // the card's measured height went on ramping around it — its
                // own transaction — so closing a tab looked unlike switching
                // to one.
                withAnimation(HelmMotion.interface) {
                    apply(layout.removingTab(tab.id))
                    activeTab = tabIndex.clamped(to: 0...max(0, layout.tabs.count - 1))
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
}

/// The bar above the grid while the panel is being arranged.
/// The bar says one thing: you are editing, and here is the way out.
///
/// It carried the tab-label picker for a while — a full-width segmented
/// control, the heaviest thing in the panel, for a decision somebody makes once,
/// inside a mode that is about arranging widgets. It also appeared and vanished
/// with the number of tabs, so it flickered on state it had nothing to do with,
/// and it argued with «Готово» for the same row. It lives in Settings → Panel
/// now, beside the other three switches about how this panel looks.
struct PanelEditBar: View {
    let done: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(AppStr.panelSetup).font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button(AppStr.done, action: done)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .helmPanelCard()
    }
}

/// Everything not on this tab, as ghosts to press.
///
/// Which ids those are is the panel's question — two independent refusals decide
/// it — and this draws the answer.
struct PanelGallery: View {
    let ids: [String]
    let byID: [String: ModuleHost.Live]
    /// The same namespace the tiles travel in, so pressing a ghost *moves* it
    /// into the grid instead of ending it here and starting it there.
    let shapes: Namespace.ID
    let add: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppStr.addWidget)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
            let columns = PanelGrid.columns(for: helmPanelWidth)
            ForEach(Array(stride(from: 0, to: ids.count, by: columns)), id: \.self) { start in
                HStack(spacing: PanelGrid.gap) {
                    ForEach(ids[start..<min(start + columns, ids.count)], id: \.self) { id in
                        ghost(id, byID[id])
                    }
                    ForEach(0..<max(0, columns - (min(start + columns, ids.count) - start)),
                            id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
        .helmPanelCard()
    }

    private func ghost(_ id: String, _ live: ModuleHost.Live?) -> some View {
        let descriptor = live?.descriptor ?? ModuleRegistry.all.first { $0.idRaw == id }
        let isDrawer = id == HelmPanelContent.utilitiesWidget
        return Button {
            add(id)
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
            .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(HelmText.faint))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Safe because the two can never be on screen together: the panel
        // offers only what no tab holds, and a tile is drawn only where it is
        // held — so this id has exactly one view at any moment.
        .matchedGeometryEffect(id: id, in: shapes)
    }
}

/// The three ways out, at the foot of the panel.
///
/// `showSettings` and `showQuit` both defaulted to false once, which is how a
/// clean install ended up with no way into settings from the panel it was given
/// — and no way to find the switch that would have added one. Not an option any
/// more.
struct PanelFooter: View {
    let editing: Bool
    let showSettings: Bool
    let showQuit: Bool
    let showEdit: Bool
    let configure: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if showSettings {
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
            // Both glyphs at the right edge, together. A lone icon floating in
            // the middle of a footer reads as something that lost its label
            // rather than as something that never needed one.
            if !editing && showEdit {
                footerGlyph("pencil", AppStr.configurePanel, action: configure)
            }
            if showQuit {
                footerGlyph("power", AppStr.quit) { NSApp.terminate(nil) }
            }
        }
        .helmPanelCard()
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
}
