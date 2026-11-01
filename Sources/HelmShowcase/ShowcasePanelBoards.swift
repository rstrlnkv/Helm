import HelmUI
import SwiftUI

// MARK: - Panel

/// Widths from the kit: one tile, and a wide tile of two tiles and the gap between.
struct PanelBoard: View {
    @Environment(\.helmTraits) private var traits
    private static let wide = 2 * PanelGrid.minimumTile + PanelGrid.gap

    var body: some View {
        Board(name: "Panel widgets", caption: """
            The kit's parts of a panel tile at the three sizes a tile has: header, figure, row, the unmeasured \
            line, the card and the scroll edges. They take no pointer state and read no window; the tile of a \
            module is not here, a module is not reachable from the showcase.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
                HStack(alignment: .top, spacing: PanelGrid.gap) {
                    HelmWidgetBody {
                        HelmWidgetHeader(symbol: "gearshape", tint: Sample.tint(traits), name: Sample.russianTitle, compact: true)
                        HelmWidgetFigure("12", Sample.short, .compact)
                    }
                    .frame(width: PanelGrid.minimumTile)
                    HelmWidgetBody {
                        HelmWidgetHeader(symbol: "gearshape", tint: Sample.tint(traits), name: Sample.russian, active: false,
                                         compact: true)
                        HelmWidgetUnmeasured(Sample.russianNote)
                    }
                    .frame(width: PanelGrid.minimumTile)
                }
                HelmWidgetBody {
                    HelmWidgetHeader(symbol: "gearshape", tint: Sample.tint(traits), name: Sample.title, subtitle: Sample.russianNote) {
                        HelmStatusDot(active: true, size: .widget)
                    }
                    HelmWidgetFigure(Sample.figure, Sample.russian, .wide)
                }
                .frame(width: Self.wide)
                HelmWidgetBody {
                    HelmWidgetHeader(symbol: "gearshape", tint: Sample.tint(traits), name: Sample.title)
                    ScrollView {
                        VStack(spacing: HelmSpace.s2) {
                            ForEach(0..<16, id: \.self) { index in
                                HelmWidgetRow(index == 1 ? Sample.russian : Sample.title,
                                              index.isMultiple(of: 2) ? Sample.figure : nil)
                            }
                        }
                    }
                    .helmPanelScrollEdges()
                    .frame(height: 140)
                }
                .frame(width: Self.wide)
            }
        }
    }

}

// MARK: - Toolbar

struct ToolbarBoard: View {
    @Environment(\.helmTraits) private var traits

    var body: some View {
        Board(name: "Header row: tabs, actions, search", caption: """
            The header row from what a page declares through helmWindowToolbar, under both bar looks. Glass is \
            over an empty ground here: the page's own shot is the proof of the look. A tab's symbol has no \
            reader, so it is empty. The search field's and the glass buttons' hover and press cannot be forced. In \
            the disabled rows the tabs and the actions are disabled; the search stays enabled.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s4) {
                bar("flat", look: .flat, content: full())
                bar("liquid glass", look: .liquidGlass, content: full())
                bar("flat, disabled", look: .flat, content: full(enabled: false))
                bar("glass, disabled", look: .liquidGlass, content: full(enabled: false))
                bar("flat, attention and busy", look: .flat, content: full(attention: true, busy: true))
                bar("flat, inactive window", look: .flat, active: false, content: full())
                bar("glass, inactive window", look: .liquidGlass, active: false, content: full())
                bar("flat, status active, long Russian", look: .flat, title: Sample.russian,
                    status: .init(word: Sample.russianTitle, active: true), content: full())
                bar("flat, status idle", look: .flat, status: .init(word: Sample.note, active: false), content: full())
            }
        }
    }

    private func bar(_ name: String, look: HelmBarAppearance, active: Bool = true, title: String = Sample.title,
                     status: HelmHeaderStatus? = nil, content: HelmPageToolbarContent) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            Text(verbatim: name).font(.caption).foregroundStyle(.secondary)
            Color.clear.frame(width: 1260, height: 0)
                .helmWindowToolbar(content, token: name)
                .helmCardHeader(symbol: "gearshape", tint: Sample.tint(traits), title: title, status: status)
                .environment(\.helmBarAppearance, look)
                .environment(\.helmWindowAppearsActive, active)
        }
    }

    private func full(enabled: Bool = true, attention: Bool = false, busy: Bool = false) -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "one", title: Sample.short, symbol: ""),
                   HelmToolbarTab(id: "two", title: Sample.russianTitle, symbol: "",
                                  needsAttention: attention, attentionNote: attention ? Sample.note : nil),
                   HelmToolbarTab(id: "three", title: Sample.title, symbol: "")],
            selectedTab: .constant("one"), tabsEnabled: enabled,
            actions: [HelmToolbarAction(id: "refresh", title: Sample.short, symbol: "arrow.clockwise",
                                        isEnabled: enabled, isBusy: busy) {},
                      HelmToolbarAction(id: "follow", title: Sample.title, symbol: "pin", isEnabled: enabled,
                                        isOn: true,
                                        face: HelmToolbarToggleFace(offSymbol: "pin.slash", onValue: Sample.short,
                                                                    offValue: Sample.title)) {},
                      HelmToolbarAction(id: "filter", title: Sample.menu, symbol: "line.3.horizontal.decrease",
                                        isEnabled: enabled,
                                        menu: [HelmToolbarMenuItem(id: "a", title: Sample.short, isOn: true) {}])],
            search: HelmToolbarSearch(prompt: Sample.russianTitle, text: .constant("")))
    }
}

// MARK: - Welcome

struct WelcomeBoard: View {
    var body: some View {
        Board(name: "Welcome", caption: """
            The first step (an intro with module glyphs) and a module step with its offer, side by side. \
            The actions are the view's defaults, which touch nothing here; Back is disabled on the first step.
            """) {
            HStack(spacing: HelmSpace.s6) {
                WelcomeView(steps: [WelcomeStep(id: "intro", sfSymbol: "sparkles", title: Sample.russianTitle,
                                                body: Sample.russianNote,
                                                moduleSymbols: ["gearshape", "tray", "star"])]) {}
                WelcomeView(steps: [WelcomeStep(id: "module", sfSymbol: "gearshape", title: Sample.russian,
                                                body: Sample.russianNote, moduleID: "sample",
                                                offer: Sample.short)]) {}
            }
        }
    }
}
