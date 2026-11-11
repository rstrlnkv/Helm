import HelmUI
import SwiftUI

/// Every sample string the boards draw. Plain `String`s handed to `Text(verbatim:)` and to the
/// `StringProtocol` initialisers, never `L(…)` and never a literal that SwiftUI would look up: sample text
/// is not a shipped string, so it belongs in none of the eight tables.
enum Sample {
    static let short = "Open"
    static let long = "Restore every module to its defaults"
    static let russian = "Восстановить параметры по умолчанию для всех модулей"
    static let note = "A note under a title, quieter than it."
    /// A removal's `succeededText`: the kit draws it as given; it adds the full stop only to the failed
    /// heading with something removed.
    static let moved = "Moved to the Trash — 1,2 ГБ"
    static let russianTitle = "Своё время"
    static let russianVerb = "Начать"
    static let russianHour = "ч"
    static let russianMinute = "мин"
    static let russianNote = "Пояснение под названием, тише него и длиннее одной строки в узком столбце."
    static let delete = "Delete"
    static let cancel = "Cancel"
    static let close = "Close"
    static let title = "Sample title"
    static let sheet = "sheet"
    static let popover = "popover"
    static let alert = "alert"
    static let dialog = "dialog"
    static let menu = "menu"
    /// The label `ChoiceCards` was measured against, and a name with spaces: no bundle id is spelled so, so
    /// `HelmAppRuleRow` finds no app and draws the generic icon and this text.
    static let russianCard = "Имя в строке меню"
    static let ruleApp = "Приложение с длинным именем"
    static let figure = "1 234,5 МБ"
    /// Computed: the type is not `Sendable`, a `static let` would not build.
    static var explainer: HelmExplainer.Content {
        .init(title: russianTitle, blocks: [.text(russianNote), .command("ls -l /private/tmp")])
    }
    static func refusals(_ count: Int) -> [HelmRemovalFailure] {
        (1...count).map { .init(path: "/private/tmp/sample-\($0).txt", reason: russianNote) }
    }

    /// A module's tint for the boards that need one: the numbers are a copy of `KeepAwakeDescriptor`'s,
    /// not read from it (the showcase depends on `HelmUI` alone), so a change to that
    /// descriptor does not reach this.
    private static let moduleTint = ModuleTint(
        ordinary: (light: (0.871, 0.478, 0.131), dark: (0.854, 0.486, 0.155)),
        increasedContrast: (light: (0.699, 0.384, 0.105), dark: (0.687, 0.391, 0.125)))

    /// The one place a board reads that tint, in the contrast the board is drawn in.
    static func tint(_ traits: HelmTraits) -> Color { moduleTint.colour(increased: traits.increasedContrast) }
}

/// A column of the state matrices. `focus` is drawn live (Tab to it, with Full Keyboard Access on); the
/// others are forced by the environment, where the kit reads one.
enum ShowcaseState: CaseIterable {
    case rest, hover, pressed, focus, disabled, selected, inactive

    var title: String {
        switch self {
        case .rest: "rest"
        case .hover: "hover"
        case .pressed: "pressed"
        case .focus: "focus (live)"
        case .disabled: "disabled"
        case .selected: "selected"
        case .inactive: "inactive window"
        }
    }

    var interaction: HelmInteraction {
        switch self {
        case .hover: .hover
        case .pressed: .pressed
        default: .live
        }
    }
}

extension [ShowcaseState] {
    /// The columns of a board whose rows have no selected look: there it would repeat rest.
    static let unselected = ShowcaseState.allCases.filter { $0 != .selected }
}

/// One row of a matrix: a label and what to draw in each column it supports; the rest show a dash.
struct ShowcaseRow {
    let label: String
    var states: [ShowcaseState] = ShowcaseState.allCases
    let cell: (ShowcaseState) -> AnyView

    init(_ label: String, states: [ShowcaseState] = ShowcaseState.allCases,
         @ViewBuilder cell: @escaping (ShowcaseState) -> some View) {
        self.label = label
        self.states = states
        self.cell = { AnyView(cell($0)) }
    }
}

struct Matrix: View {
    let rows: [ShowcaseRow]
    var columns: [ShowcaseState] = ShowcaseState.allCases
    var cellWidth: CGFloat = 118

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 12) {
            GridRow {
                Color.clear.frame(width: 130, height: 1)
                ForEach(columns, id: \.self) { state in
                    Text(verbatim: state.title).font(.caption).foregroundStyle(.secondary)
                        .frame(width: cellWidth, alignment: .leading)
                }
            }
            Divider().gridCellColumns(columns.count + 1)
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                GridRow {
                    Text(verbatim: row.label).font(.caption).foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .leading)
                    ForEach(columns, id: \.self) { state in
                        Group {
                            if row.states.contains(state) {
                                row.cell(state)
                                    .environment(\.helmShownInteraction, state.interaction)
                                    .environment(\.helmWindowAppearsActive, state != .inactive)
                                    .disabled(state == .disabled)
                            } else {
                                Text(verbatim: "—").foregroundStyle(.tertiary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: cellWidth, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// A board's frame: its name, a caption saying what cannot be forced on it, then the content.
struct Board<Content: View>: View {
    let name: String
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s6) {
            Text(verbatim: name).font(.title3.weight(.semibold))
            Text(verbatim: caption).font(.caption).foregroundStyle(.secondary)
                .frame(width: 900, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(20)
        .frame(minWidth: 520, alignment: .topLeading)
        .fixedSize()
    }
}

enum ShowcaseBoards {
    @MainActor static func view(for options: ShowcaseOptions) -> AnyView {
        switch options.board {
        case .buttons: AnyView(ButtonsBoard())
        case .capsules: AnyView(CapsulesBoard())
        case .toggles: AnyView(TogglesBoard())
        case .rows: AnyView(RowsBoard())
        case .sections: AnyView(SectionsBoard())
        case .hotkeys: AnyView(HotkeysBoard())
        case .notices: AnyView(NoticesBoard())
        case .header: AnyView(HeaderBoard())
        case .toolbar: AnyView(ToolbarBoard())
        case .surfaces: AnyView(SurfacesBoard())
        case .pickers: AnyView(PickersBoard())
        case .lists: AnyView(ListsBoard())
        case .panel: AnyView(PanelBoard())
        case .motion: AnyView(MotionBoard())
        case .palette: AnyView(PaletteBoard())
        case .ladders: AnyView(LaddersBoard())
        case .present: AnyView(PresentBoard(initial: options.presentation))
        case .welcome: AnyView(WelcomeBoard())
        }
    }
}

// MARK: - Buttons

private struct ButtonsBoard: View {
    var body: some View {
        Board(name: "Buttons", caption: """
            Kit rows are a plain Button under the root's HelmButtonStyle; system rows name .bordered, so the \
            two sit side by side (the open owner points: .large padding, and the kit's fill against the \
            system's). The default action names .borderedProminent itself. Focus is the live system ring: it \
            needs the key window and Full Keyboard Access. The inactive column sets the kit's own window \
            value; a system control draws its inactive look only in a real inactive window. The window is not \
            the key window when it is photographed (a bare binary asked to activate stays inactive): the \
            default action is grey there, the focus column is the rest look, and the system rows' own \
            hover and pressed look cannot be forced, so those columns show them at rest. A press where a control has \
            only the system's plain one is not forced either. There is no selected column: a button's chosen \
            look is helmChosen, on capsules, with the destructive and capsule rows. The short busy label row \
            holds a spinner in hover, pressed and disabled, the long Russian one in both of its.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
            Matrix(rows: [
                ShowcaseRow("kit", states: .unselected) { _ in Button(Sample.short) {} },
                ShowcaseRow("system .bordered", states: .unselected) { _ in Button(Sample.short) {}.buttonStyle(.bordered) },
                ShowcaseRow("kit, long Russian", states: [.rest, .hover, .pressed, .disabled]) { _ in
                    Button(Sample.russian) {}.multilineTextAlignment(.center)
                },
                ShowcaseRow("system, long Russian", states: [.rest, .disabled]) { _ in
                    Button(Sample.russian) {}.buttonStyle(.bordered).multilineTextAlignment(.center)
                },
                ShowcaseRow("kit .large", states: .unselected) { _ in Button(Sample.short) {}.controlSize(.large) },
                ShowcaseRow("system .large", states: .unselected) { _ in
                    Button(Sample.short) {}.buttonStyle(.bordered).controlSize(.large)
                },
                ShowcaseRow("default action", states: .unselected) { _ in
                    Button(Sample.short) {}.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                },
                ShowcaseRow("icon only, named", states: [.rest, .hover, .pressed, .disabled]) { _ in
                    Button { } label: { Image(systemName: "gearshape") }.accessibilityLabel(Sample.title)
                },
                ShowcaseRow("busy label", states: [.rest, .hover, .pressed, .disabled]) { state in
                    Button {} label: { HelmBusyLabel(Sample.russianVerb, busy: state != .rest) }
                },
            ], columns: .unselected)
            Matrix(rows: [
                ShowcaseRow("busy label, long Russian", states: [.rest, .disabled]) { _ in
                    Button {} label: { HelmBusyLabel(Sample.russian, busy: true) }.multilineTextAlignment(.center)
                },
            ], columns: [.rest, .disabled], cellWidth: 240)
            }
        }
    }
}

// MARK: - Capsules

private struct CapsulesBoard: View {
    var body: some View {
        Board(name: "Capsules and destructive", caption: """
            The capsule family: helmCapsuleButtons, helmChosen (the chosen well wins over the pointer and \
            over disabled: in the capsule row, a matrix of its own, the chosen button's well is the same in \
            every column, its ink dims in disabled, and the other two change), the destructive buttons of \
            the kit and of the system, the row menu and the remove button. There is no selected column: the chosen look is the capsule row. The \
            system's hover and pressed look cannot be forced; the row menu's open content cannot either, and \
            the remove button has only the system's plain press. Focus is the live ring and needs the key \
            window and Full Keyboard Access.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
            Matrix(rows: [
                ShowcaseRow("kit destructive", states: .unselected) { _ in Button(Sample.delete, role: .destructive) {} },
                ShowcaseRow("kit capsule (Keep Awake hero)", states: [.rest, .hover, .pressed, .disabled]) { _ in
                    Button(Sample.short) {}.controlSize(.large).helmCapsuleButtons()
                },
                ShowcaseRow("kit capsule destructive", states: .unselected) { _ in
                    Button(Sample.delete, role: .destructive) {}.helmCapsuleButtons()
                },
                ShowcaseRow("system destructive", states: .unselected) { _ in
                    Button(Sample.delete, role: .destructive) {}.buttonStyle(.bordered)
                },
                ShowcaseRow("capsule, long Russian", states: [.rest, .hover, .pressed, .disabled]) { _ in
                    Button(Sample.russian) {}.multilineTextAlignment(.center).helmCapsuleButtons()
                },
                ShowcaseRow("destructive, long Russian", states: [.rest, .hover, .pressed, .disabled]) { _ in
                    Button(Sample.russian, role: .destructive) {}.multilineTextAlignment(.center)
                },
                ShowcaseRow("row menu (HelmRowMenu)", states: .unselected) { _ in
                    HelmRowMenu(subject: Sample.title) { Button(Sample.short) {} }
                },
                ShowcaseRow("remove button", states: [.rest, .focus, .disabled, .inactive]) { _ in
                    HelmRemoveButton(label: Sample.title) {}
                },
                ShowcaseRow("remove button, 28 pt target", states: [.rest, .focus, .disabled, .inactive]) { _ in
                    HelmRemoveButton(label: Sample.title, target: 28) {}
                },
            ], columns: .unselected)
            Matrix(rows: [
                ShowcaseRow("kit capsule row, one chosen", states: [.rest, .hover, .pressed, .disabled]) { _ in
                    HStack(spacing: HelmSpace.s3) {
                        Button(Sample.short) {}.helmChosen(true)
                        Button(Sample.title) {}.helmChosen(false)
                        Button(Sample.delete) {}.helmChosen(false)
                    }.helmCapsuleButtons()
                },
            ], columns: [.rest, .hover, .pressed, .disabled], cellWidth: 240)
            }
        }
    }
}

// MARK: - Toggles

/// `HelmPillChoice`: each option chosen in turn, a long Russian pair, and one disabled.
private struct PillChoiceSamples: View {
    @State private var first = 0
    @State private var second = 1
    @State private var third = 0

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            pills(Sample.title, $first, [Sample.short, Sample.title])
            pills(Sample.title, $second, [Sample.short, Sample.title])
            pills(Sample.russian, $third, [Sample.russian, Sample.russianNote])
            pills(Sample.title, $first, [Sample.short, Sample.title]).disabled(true)
        }
    }

    private func pills(_ title: String, _ selection: Binding<Int>, _ labels: [String]) -> some View {
        HelmPillChoice(title, selection: selection, items: labels.enumerated().map { index, label in
            .init(index, label: label,
                  chosenFill: HelmSurface.chosenWash(index == 0 ? .accentColor : HelmSignal.warning),
                  help: label)
        })
    }
}

private struct TogglesBoard: View {
    var body: some View {
        Board(name: "Toggles", caption: """
            HelmToggleStyle sets the row; the switch is the system's, so its hover and pressed look cannot be \
            forced and those columns are dashes. Selected is the switch on; every other column is off. In a \
            window that is not the key window the switch on loses its accent fill and its track differs from the off \
            one only slightly (1.12:1 in light), and the focus column is the rest look. The checkbox is the \
            system's and its slot is the empty space where a row has none; the pills' hover and press are \
            the system's plain press, not forced.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
            Matrix(rows: [
                row("kit"),
                row("long Russian label", label: Sample.russian),
                row("kit .large", size: .large),
                row("kit .small", size: .small),
                ShowcaseRow("labels hidden, named", states: Self.switchStates) { state in
                    Toggle(Sample.short, isOn: .constant(state == .selected)).labelsHidden()
                        .accessibilityLabel(Sample.title)
                },
                ShowcaseRow("checkbox above its slot", states: Self.switchStates) { state in
                    VStack(alignment: .leading, spacing: HelmSpace.s2) {
                        Toggle(Sample.short, isOn: .constant(state == .selected)).toggleStyle(.checkbox)
                        HStack(spacing: HelmSpace.s3) { HelmCheckboxSlot(); Text(verbatim: Sample.short) }
                    }
                },
            ], columns: Self.switchStates, cellWidth: 220)
            PillChoiceSamples()
            }
        }
    }

    private static let switchStates: [ShowcaseState] = [.rest, .focus, .disabled, .selected, .inactive]

    private func row(_ name: String, label: String = Sample.short, size: ControlSize = .regular) -> ShowcaseRow {
        ShowcaseRow(name, states: Self.switchStates) { state in
            Toggle(label, isOn: .constant(state == .selected)).controlSize(size)
        }
    }
}

// MARK: - Rows

private struct RowsBoard: View {
    var body: some View {
        Board(name: "Rows", caption: """
            The sidebar row's pressed state is the system's, so that column is a dash; selected keeps its \
            fill in an inactive window and dims the glyph and name (the last sidebar row, selected and \
            inactive together). Focus is the rest look in a window that is not the key window. The settings \
            sections and the banners are on sections and notices.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
                Matrix(rows: [
                    sidebar("sidebar row", Sample.short),
                    sidebar("long Russian", Sample.russian),
                    ShowcaseRow("selected, inactive window", states: [.inactive]) { _ in
                        HelmSidebarRow(title: Sample.short, glyph: .settings, selected: true, collapsed: false) {}
                            .frame(width: 118)
                    },
                    ShowcaseRow("collapsed", states: [.rest, .hover, .focus, .disabled, .selected, .inactive]) { state in
                        HelmSidebarRow(title: Sample.short, glyph: .settings, selected: state == .selected,
                                       collapsed: true) {}
                            .frame(width: 44)
                    },
                    ShowcaseRow("with warning", states: [.rest, .hover, .selected, .inactive]) { state in
                        HelmSidebarRow(title: Sample.short, glyph: .settings, selected: state == .selected,
                                       collapsed: false,
                                       warning: .init(mark: Sample.note, spoken: Sample.note)) {}
                            .frame(width: 118)
                    },
                ])
                VStack(spacing: 0) {
                    ForEach([HelmRowMark.none, .space, .holding, .waiting, .attention], id: \.self) { mark in
                        HelmSettingRow(Sample.title, note: Sample.note, mark: mark) {
                            Toggle(Sample.title, isOn: .constant(true)).labelsHidden()
                        }
                        .padding(.vertical, HelmSpace.s3)
                    }
                    HelmSettingRow(Sample.russian, note: Sample.russianNote) {
                        Button(Sample.short) {}
                    }
                    .padding(.vertical, HelmSpace.s3)
                }
                .helmCard()
                .frame(width: 560)
            }
        }
    }

    private func sidebar(_ name: String, _ title: String) -> ShowcaseRow {
        ShowcaseRow(name, states: [.rest, .hover, .focus, .disabled, .selected, .inactive]) { state in
            HelmSidebarRow(title: title, glyph: .settings, selected: state == .selected, collapsed: false) {}
                .frame(width: 118)
        }
    }
}

// MARK: - Header

private struct HeaderBoard: View {
    @Environment(\.helmTraits) private var traits

    var body: some View {
        Board(name: "Page header", caption: """
            Hover is forced by the kit's seam, and the band also needs the window to be key, so only the hover \
            row sets the key state itself; every other row reads the window's own state. The inactive row is the settings window's \
            header, which dims in a window that is not the active one; the public header view alone does not \
            dim (it takes no window value), and that row has no trailing control and bleeds to the edge like the settings window's. \
            No band is macOS 26's look; over a scroll view the band waits for content. Tabs, actions and search are on toolbar.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                header("rest")
                header("hover", interaction: .hover).environment(\.controlActiveState, .key)
                inactiveHeader
                header("disabled trailing control", disabled: true)
                header("long Russian title", title: Sample.russian)
                header("bleeds, stands on still content", bleeds: true, still: true)
                header("macOS 26: no band").environment(\.helmBandChoice, .onMacOS(26))
                VStack(alignment: .leading, spacing: HelmSpace.s2) {
                    Text(verbatim: "over a scroll view").font(.caption).foregroundStyle(.secondary)
                    ScrollView { Color.clear.frame(width: 760, height: 240) }
                        .helmPageHeader(symbol: "gearshape", tint: Sample.tint(traits), title: Sample.title)
                        .frame(width: 760, height: 100)
                }
            }
        }
    }

    private var inactiveHeader: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            Text(verbatim: "inactive window").font(.caption).foregroundStyle(.secondary)
            Color.clear.frame(width: 760, height: 0)  // the header reserves its own height above it
                .helmCardHeader(symbol: "gearshape", tint: Sample.tint(traits), title: Sample.title, status: nil)
                .environment(\.helmWindowAppearsActive, false)
        }
    }

    private func header(_ name: String, title: String = Sample.title, interaction: HelmInteraction = .live,
                        disabled: Bool = false, bleeds: Bool = false,
                        still: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            Text(verbatim: name).font(.caption).foregroundStyle(.secondary)
            HelmPageHeader(symbol: "gearshape", tint: Sample.tint(traits), title: title, bleeds: bleeds,
                           standsOnStillContent: still) {
                Button(Sample.short) {}.disabled(disabled)
            }
            .environment(\.helmShownInteraction, interaction)
            .frame(width: 760)
        }
    }
}

// MARK: - Surfaces

private struct SurfacesBoard: View {
    @Environment(\.helmTraits) private var traits
    private static let states: [ShowcaseState] = [.rest, .disabled, .inactive]

    var body: some View {
        Board(name: "Surfaces and marks", caption: """
            Components that take no pointer state: each drawn in its variants, tinted with the kit's own \
            signal colours and the sample module tint. Light and dark, and the contrast pair, come from \
            --appearance. The columns of the matrix are drawn by one expression and nothing here reads the \
            pointer, isEnabled or the window, so the claim "no such state" is on the screen; that two cells \
            match to the pixel is not claimed. HelmAppMark's ring is the fallback stroke: an unbundled binary has no helm-ring.svg. \
            The empty and busy states are on notices.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
                HStack(alignment: .top, spacing: HelmSpace.s6) {
                    HelmAppHero(active: false, tagline: Sample.note, spoken: Sample.title) {
                        HelmBadge(Sample.short, tint: warning, emphasis: .prominent)
                    }
                    HelmAppHero(active: true, tagline: Sample.russianNote, spoken: Sample.title) {
                        HelmBadge(Sample.short, tint: Sample.tint(traits), emphasis: .prominent)
                    }
                    .frame(width: 300)
                }
                HStack(alignment: .top, spacing: HelmSpace.s6) {
                    Text(verbatim: Sample.note).helmCard().frame(width: 200)
                    Text(verbatim: Sample.note).helmCard().helmPreviewEdge(chosen: true).frame(width: 200)
                    Text(verbatim: Sample.note).helmCard().helmPreviewEdge().frame(width: 200)
                    HelmAppMark(size: 44)
                    HelmWallpaper(dark: false).frame(width: 74, height: 46).helmPreviewEdge()
                    HelmWallpaper(dark: true).frame(width: 74, height: 46).helmPreviewEdge(chosen: true)
                    Text(verbatim: Sample.short).padding(.horizontal, HelmSpace.s4).padding(.vertical, HelmSpace.s1)
                        .helmPillTrack()
                }
                Matrix(rows: [
                    ShowcaseRow("icon plate, on and off", states: Self.states) { _ in
                        HStack {
                            HelmIconPlate(symbol: "gearshape", tint: Sample.tint(traits))
                            HelmIconPlate(symbol: "gearshape", tint: Sample.tint(traits), active: false)
                        }
                    },
                    ShowcaseRow("signal plate", states: Self.states) { _ in
                        HelmSignalPlate(symbol: "checkmark", tint: success)
                    },
                    ShowcaseRow("badges", states: Self.states) { _ in
                        HStack {
                            HelmBadge(Sample.short)
                            HelmBadge(Sample.short, tint: warning)
                            HelmBadge(Sample.short, tint: danger, emphasis: .prominent)
                        }
                    },
                    ShowcaseRow("badge, long Russian", states: Self.states) { _ in
                        HelmBadge(Sample.russian, tint: success)
                    },
                    ShowcaseRow("status dots", states: Self.states) { _ in
                        HStack {
                            HelmStatusDot(active: true)
                            HelmStatusDot(active: true, size: .widget)
                            HelmStatusDot(active: false)
                        }
                    },
                ], columns: Self.states, cellWidth: 180)
                HelmSectionTitle(Sample.title)
                HelmMetricStrip([.init("12", Sample.short), .init("3.4", Sample.title, tint: Sample.tint(traits)),
                                 .init("0", Sample.russian)]).frame(width: 560)
            }
        }
    }

    private var success: Color { HelmSignal.success(increased: traits.increasedContrast) }
    private var warning: Color { HelmSignal.warning(increased: traits.increasedContrast) }
    private var danger: Color { HelmSignal.danger(increased: traits.increasedContrast) }
}

// MARK: - Palette

private struct PaletteBoard: View {
    @Environment(\.helmTraits) private var traits

    var body: some View {
        Board(name: "Palette", caption: """
            Fills over the window ground, the three inks, the signal colours and one sample module tint \
            (sample values a copy of KeepAwake's descriptor, not read from it; the real \
            ones are declared by each descriptor). Signal and tint \
            follow Increase Contrast through --appearance light-contrast and dark-contrast. The row of \
            images is PaletteColor.swatchImage, the pre-coloured menu swatches.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
                HStack(spacing: HelmSpace.s5) {
                    fill("cardFill", HelmSurface.cardFill)
                    fill("wellFill", HelmSurface.wellFill)
                    fill("onPanelFill", HelmSurface.onPanelFill)
                    fill("panelCardFill", HelmSurface.panelCardFill)
                    fill("hairline", HelmSurface.hairline)
                    fill("panelSelection", HelmSurface.panelSelection)
                    fill("barPick", HelmSurface.barPick)
                    fill("rowSelection", HelmSurface.rowSelection)
                    fill("rowHover", HelmSurface.rowHover)
                    fill("barPlate", HelmSurface.barPlate)
                    fill("chosenWash", HelmSurface.chosenWash(.accentColor))
                }
                VStack(alignment: .leading, spacing: HelmSpace.s2) {
                    Text(verbatim: "primary \(Sample.note)")
                    Text(verbatim: "quiet \(Sample.note)").foregroundStyle(HelmText.quiet)
                    Text(verbatim: "faint \(Sample.note)").foregroundStyle(HelmText.faint)
                    Text(verbatim: "separator").foregroundStyle(HelmText.separator)
                }
                HStack(spacing: HelmSpace.s5) {
                    ink("warning", HelmSignal.warning(increased: traits.increasedContrast))
                    ink("success", HelmSignal.success(increased: traits.increasedContrast))
                    ink("danger", HelmSignal.danger(increased: traits.increasedContrast))
                    ink("module tint", Sample.tint(traits))
                    VStack(spacing: HelmSpace.s2) {
                        RoundedRectangle(cornerRadius: HelmRadius.ctl).fill(Color.accentColor).frame(width: 80, height: 56)
                            .overlay { Text(verbatim: Sample.short).foregroundStyle(HelmText.onFill) }
                        Text(verbatim: "onFill").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: HelmSpace.s3) {
                    ForEach(PaletteColor.offered, id: \.rawValue) { colour in
                        Image(nsImage: colour.swatchImage)
                    }
                }
            }
        }
    }

    private func fill(_ name: String, _ colour: Color) -> some View {
        VStack(spacing: HelmSpace.s2) {
            RoundedRectangle(cornerRadius: HelmRadius.ctl).fill(colour).frame(width: 80, height: 56)
            Text(verbatim: name).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func ink(_ name: String, _ colour: Color) -> some View {
        VStack(spacing: HelmSpace.s2) {
            RoundedRectangle(cornerRadius: HelmRadius.ctl).fill(colour).frame(width: 80, height: 56)
            Text(verbatim: name).font(.caption).foregroundStyle(colour)
        }
    }
}

// MARK: - Ladders

private struct LaddersBoard: View {
    var body: some View {
        Board(name: "Ladders and type", caption: """
            HelmSpace steps as widths, HelmRadius steps as corners, HelmText faces, and the figure modifiers \
            over a Russian figure and sentence.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
                HStack(alignment: .bottom, spacing: HelmSpace.s5) {
                    ForEach(Array([HelmSpace.s1, HelmSpace.s2, HelmSpace.s3, HelmSpace.s4, HelmSpace.s5,
                                   HelmSpace.s6, HelmSpace.s7, HelmSpace.s8].enumerated()), id: \.offset) { step in
                        VStack(spacing: HelmSpace.s2) {
                            Rectangle().fill(Color.primary.opacity(0.5)).frame(width: step.element, height: 40)
                            Text(verbatim: "s\(step.offset + 1) \(Int(step.element))").font(.caption2)
                        }
                    }
                }
                HStack(spacing: HelmSpace.s5) {
                    ForEach(Array([("ctl", HelmRadius.ctl), ("card", HelmRadius.card), ("frame", HelmRadius.frame),
                                   ("window", HelmRadius.window), ("panel", HelmRadius.panel)].enumerated()),
                            id: \.offset) { step in
                        VStack(spacing: HelmSpace.s2) {
                            RoundedRectangle(cornerRadius: step.element.1, style: .continuous)
                                .fill(HelmSurface.panelSelection).frame(width: 90, height: 60)
                            Text(verbatim: "\(step.element.0) \(Int(step.element.1))").font(.caption2)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: HelmSpace.s3) {
                    Text(verbatim: Sample.title).font(HelmText.rowTitle)
                    Text(verbatim: Sample.note).font(HelmText.rowDetail)
                    Text(verbatim: Sample.title).font(HelmText.sectionHeading)
                    Text(verbatim: Sample.title).font(HelmText.groupLabel)
                    Text(verbatim: "1 234,5 MB").font(HelmText.figureFont)
                    Text(verbatim: "1 234").font(HelmText.metricFont)
                    Text(verbatim: "42").font(HelmText.heroFont)
                    Text(verbatim: Sample.russian).font(HelmText.rowTitle)
                    Text(verbatim: Sample.title).font(HelmText.plateTitle)
                    Text(verbatim: Sample.title).font(HelmText.entryHeading)
                    Text(verbatim: "checkmark.circle").font(HelmText.statusGlyph)
                    Text(verbatim: Sample.note).font(HelmText.smallPrint)
                    Text(verbatim: Sample.note).font(HelmText.pictureCaption)
                    Text(verbatim: "ls -l /private/tmp").font(HelmText.code)
                    Text(verbatim: "42").font(HelmText.heroFigureFont)
                    Text(verbatim: Sample.figure).helmFigure()
                    Text(verbatim: Sample.figure).helmMetricFigure()
                    Text(verbatim: Sample.russianNote).helmHeroSentence().frame(width: 320)
                }
            }
        }
    }
}

// MARK: - Present

private struct PresentBoard: View {
    @State private var sheet: Bool
    @State private var popover: Bool
    @State private var alert: Bool
    @State private var dialog: Bool
    @State private var zeroMinutes = 0
    @State private var setMinutes = 90

    init(initial: ShowcaseOptions.Presentation?) {
        _sheet = State(initialValue: initial == .sheet)
        _popover = State(initialValue: initial == .popover)
        _alert = State(initialValue: initial == .alert)
        _dialog = State(initialValue: initial == .dialog)
    }

    var body: some View {
        Board(name: "Presentations", caption: """
            Sheet, popover, alert and confirmation dialog; --present opens one at launch (one per launch), \
            and each button opens it again. A presentation opens its own root, which does not carry the \
            kit's button and toggle styles, so the sheet and the popover show the system's controls here. \
            A Menu's open content cannot be forced on a screen: click it. Under the buttons, the content of a «for how long» \
            popover twice: at zero, where its verb is disabled, and at 90 minutes.
            """) {
            HStack(spacing: HelmSpace.s5) {
                Button(Sample.sheet) { sheet = true }
                Button(Sample.popover) { popover = true }
                    .popover(isPresented: $popover) { content }
                Button(Sample.alert) { alert = true }
                Button(Sample.dialog) { dialog = true }
                Menu(Sample.menu) {
                    Button(Sample.short) {}
                    Button(Sample.delete, role: .destructive) {}
                    Toggle(Sample.title, isOn: .constant(true))
                }
                .fixedSize()
            }
            .sheet(isPresented: $sheet) { content.frame(width: 320) }
            .alert(Sample.title, isPresented: $alert) {
                Button(Sample.cancel, role: .cancel) {}
                Button(Sample.delete, role: .destructive) {}
            } message: { Text(verbatim: Sample.note) }
            .confirmationDialog(Sample.title, isPresented: $dialog, titleVisibility: .visible) {
                Button(Sample.delete, role: .destructive) {}
                Button(Sample.cancel, role: .cancel) {}
            } message: { Text(verbatim: Sample.note) }
            HStack(alignment: .top, spacing: HelmSpace.s7) {
                prompt($zeroMinutes)
                prompt($setMinutes)
            }
        }
    }

    private func prompt(_ minutes: Binding<Int>) -> some View {
        HelmDurationPrompt(Sample.russianTitle, minutes: minutes, ceiling: 1440,
                           hourLabel: Sample.russianHour, minuteLabel: Sample.russianMinute, verb: Sample.russianVerb) {}
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            Text(verbatim: Sample.title).font(HelmText.sectionHeading)
            Text(verbatim: Sample.russianNote).font(HelmText.rowDetail)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(Sample.title, isOn: .constant(true))
            HStack {
                Button(Sample.cancel) { popover = false; sheet = false }
                Button(Sample.close) { popover = false; sheet = false }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}
