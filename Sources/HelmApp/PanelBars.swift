import AppKit
import SwiftUI
import HelmRuntime
import HelmUI

// The rows of the card that are not tiles: the tab strip, the gallery of
// widgets no tab is holding, and the footer. Drawn by the card in
// `HelmPanel.swift`, which keeps the grid and everything the drag touches.
//
// Each takes what it needs and owns none of it. That is the rule the split was
// made under: the panel's `@State` is what the third drag architecture was
// bought with (ARCHITECTURE.md § The menu-bar panel), so nothing here holds state
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
    /// What the person asked for. What the strip *wears* is `TabStripFit`'s
    /// answer to it, which is not always the same: `automatic` is a question,
    /// and glyphs are refused to a strip that has a tab without one.
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

    /// Every tab's name and glyph, asked once for the whole strip.
    ///
    /// A name is `AppStr.tabTitle`, which is a table lookup, and the fit below
    /// measures each of them — so both are questions about the *strip* and
    /// neither belongs inside the loop that draws a tab. `tabButton` used to ask
    /// for its own title again, which made every name two lookups a pass.
    private var named: [(title: String, glyph: String?)] {
        layout.tabs.enumerated().map { (AppStr.tabTitle($1, number: $0 + 1), $1.glyph) }
    }

    var body: some View {
        // The setting, resolved. Asked for names or for both, that is what is
        // drawn; asked to work it out, `TabStripFit` measures these names
        // against the panel's own width. Either way it is the one place that
        // can answer «glyph», and it refuses to on a strip where a tab has none
        // — that tab drew an empty padded button.
        let named = self.named
        let face = TabStripFit.face(for: labels, tabs: named, editing: editing,
                                    available: helmPanelWidth - PanelGrid.padding * 2)
        // 2 pt between capsules: a selected capsule's fill is the only edge a
        // tab has, so the gap is what keeps two neighbours from reading as one.
        return HStack(spacing: 2) {
            ForEach(Array(layout.tabs.enumerated()), id: \.element.id) { index, tab in
                tabButton(index, tab, named[index].title, face)
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
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
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

    private func tabButton(_ index: Int, _ tab: PanelLayout.Tab,
                           _ title: String, _ face: TabLabelFace) -> some View {
        // The title is handed in. The label, the tooltip, the accessibility
        // label and the rename's draft are the same sentence, and it was built
        // four times — and once more by the fit above, which needs every name to
        // decide whether any of them is drawn.
        Button {
            // The strip and the grid move together: the selection slides while
            // the widgets under it cross-fade, on one transaction rather than
            // two.
            withAnimation(HelmMotion.interface) { activeTab = index }
        } label: {
            // The tab as the Liquid Glass mockup drew it (direction B): a
            // capsule 26 pt tall, 10 pt of padding either side, 4 pt between
            // glyph and text, and type that does **not** change weight when
            // selected.
            //
            // Weight was the first thing tried and it is the one thing a tab
            // cannot do: bold is wider than regular, so every tab in the strip
            // moved whenever another was picked. Selection is a fill and a
            // colour.
            HStack(spacing: 4) {
                if face.showsGlyph, let glyph = tab.glyph {
                    Image(systemName: glyph)
                        .font(.system(size: 13, weight: .medium))
                }
                if face.showsText {
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
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                if index == tabIndex {
                    // A fill, not a material. The panel is already Liquid
                    // Glass, and a material under the tab was glass drawn on
                    // glass with a shadow nothing could see. 12% rather than
                    // `wellFill`'s 5%, which measured 1.23:1 over the panel's
                    // glass and 1.04:1 in light. A capsule, because 13 pt is
                    // half its height and the panel's 26 pt corner is twice
                    // that: the selection sits concentric with the card.
                    Capsule()
                        .fill(HelmSurface.panelSelection)
                        // One shape that moves between tabs rather than one
                        // appearing while another goes.
                        .matchedGeometryEffect(id: "tab.selection", in: selection)
                }
            }
            .contentShape(Capsule())
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

/// The three ways out, at the foot of the panel — and, while the panel is
/// being arranged, the one way back.
///
/// `showSettings` and `showQuit` both defaulted to false once, which is how a
/// clean install ended up with no way into settings from the panel it was given
/// — and no way to find the switch that would have added one. They default to
/// true now, which is what makes the three of them safe to offer at all.
///
/// **A row under a rule, not a card** (the Liquid Glass mockup, direction B).
/// The panel is the glass; a card at its foot was one more box inside it, and
/// the controls in it are the kind a menu ends with, which a menu separates
/// with a line. In the mode the same row says what the mode is and carries
/// «Готово»: the setup bar that used to stand above the footer made the way
/// out the second row from the bottom, beside a footer still offering the
/// buttons of the mode being left.
struct PanelFooter: View {
    let editing: Bool
    let showSettings: Bool
    let showQuit: Bool
    let showEdit: Bool
    let configure: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(HelmSurface.hairline)
                .frame(height: 0.5)
                .padding(.horizontal, 4)
            Group {
                if editing {
                    HStack(spacing: 8) {
                        Text(AppStr.panelSetup)
                            .font(HelmText.rowDetail)
                            .foregroundStyle(HelmText.quiet)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button(AppStr.done, action: done)
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                } else {
                    HStack(spacing: 2) {
                        if showSettings {
                            footerButton(AppStr.settingsPane, "gearshape") {
                                NotificationCenter.default.post(name: .helmOpenSettings,
                                                                object: SettingsWindow.settingsPage)
                            }
                        }
                        Spacer(minLength: 8)
                        // A glyph, not a word. «Настроить панель» is the longest
                        // label in the footer and the least often pressed — it
                        // is the door to a mode somebody enters once and then
                        // leaves alone — and at 300 pt it was the label that ran
                        // out of room and truncated to «Настроить па…». A pencil
                        // is the one glyph macOS uses for exactly this, and the
                        // name is still there for a pointer that rests on it and
                        // for VoiceOver.
                        // Both glyphs at the right edge, together. A lone icon
                        // floating in the middle of a footer reads as something
                        // that lost its label rather than as something that
                        // never needed one.
                        if showEdit {
                            footerGlyph("pencil", AppStr.editPanel, action: configure)
                        }
                        if showQuit {
                            footerGlyph("power", AppStr.quit) { NSApp.terminate(nil) }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .frame(height: 32)
        }
    }

    /// A footer action with no room for its name: the name is the tooltip and
    /// the accessibility label, which is the whole of what the word was doing.
    /// 28 pt square, where it was 22 × 18: with no card around it the glyph's
    /// own frame is all a pointer has to land on.
    private func footerGlyph(_ symbol: String, _ name: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HelmText.quiet)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
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
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
