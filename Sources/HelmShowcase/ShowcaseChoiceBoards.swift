import HelmUI
import SwiftUI

// MARK: - Pickers

struct PickersBoard: View {
    var body: some View {
        Board(name: "Pickers", caption: """
            Pop-ups and segments are the system's, so their hover, press and open content cannot be forced \
            (pop-ups closed here); the cards, glyph choices and the appearance picker are plain buttons, \
            whose press is the system's dimming. The icon pickers and the colour swatches take no pointer here \
            (hit testing is off; an accessibility press still acts, and the last item of the colour menu opens the shared colour \
            panel). Appearance picker titles are Sample's; the captions under its pictures are the kit's own \
            words, so --language ru shows those in Russian. The menu-bar icons are every shape: neutral at \
            every size, tinted and a progress at .small only.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
                // Three lines, not a ForEach: `AppAppearance` cannot be named here (the target reaches `HelmUI` alone).
                VStack(alignment: .leading, spacing: HelmSpace.s3) {
                    AppearancePicker(selection: .constant(.light), title: Sample.title)
                    AppearancePicker(selection: .constant(.dark), title: Sample.russian)
                    AppearancePicker(selection: .constant(.system), title: Sample.title).disabled(true)
                }
                HStack(alignment: .top, spacing: HelmSpace.s6) {
                    cards(selection: 1)
                    cards(selection: 2)
                    cards(selection: 1).disabled(true)
                }
                HStack(alignment: .top, spacing: HelmSpace.s6) {
                    HelmGlyphPicker(selected: nil) { _ in }
                    HelmGlyphPicker(selected: "star") { _ in }
                    HelmGlyphPicker(selected: "star") { _ in }.disabled(true)
                }
                HStack(alignment: .top, spacing: HelmSpace.s6) {
                    IconShapePicker(selection: .constant(MenuBarIconStyle.allCases[0].rawValue), title: Sample.russian)
                    IconSizePicker(selection: .constant(MenuBarIconSize.allCases[0].rawValue))
                    HelmPaletteSwatches(Sample.title, selection: PaletteColor.offered[0].rawValue) { _ in }
                    HelmPaletteSwatches(Sample.title, selection: "#336699") { _ in }
                }
                .allowsHitTesting(false)
                Grid {
                    ForEach(MenuBarIconStyle.allCases, id: \.rawValue) { style in
                        GridRow {
                            ForEach(MenuBarIconSize.allCases, id: \.rawValue) { size in
                                Image(nsImage: MenuBarIcon.make(style: style, size: size, tintToken: nil))
                                    .renderingMode(.template)
                            }
                            Image(nsImage: MenuBarIcon.make(style: style, size: .small,
                                                            tintToken: PaletteColor.offered[1].rawValue))
                            Image(nsImage: MenuBarIcon.make(style: style, size: .small, tintToken: nil, progress: 0.4))
                                .renderingMode(.template)
                        }
                    }
                }
            }
        }
    }

    private func cards(selection: Int) -> some View {
        HelmChoiceCards(selection: .constant(selection), items: [
            .init(id: 1, label: Sample.short, preview: HelmWallpaper(dark: false)),
            .init(id: 2, label: Sample.russianCard, preview: HelmWallpaper(dark: true)),
        ], thumbnail: CGSize(width: 104, height: 46))
    }
}

// MARK: - Lists

struct ListsBoard: View {
    var body: some View {
        Board(name: "Lists", caption: """
            The striped list over a List, a checkbox or the empty slot that holds its place, a figure column; \
            selection in a List is the page's own, so it is not drawn here. The rule rows name no installed app \
            (a name with spaces finds none), so the icon is the generic one and nothing on this Mac enters a shot. \
            Remove has only the system's plain press. The removal outcome has three verdicts: succeeded, failed \
            and silent, which draws nothing, so it has no block; its buttons (Finder, Grant) take no pointer \
            here, because they act on the machine (an accessibility press still acts).
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
                List(0..<6, id: \.self) { index in
                    HStack(spacing: HelmSpace.s3) {
                        if index.isMultiple(of: 2) {
                            Toggle(Sample.short, isOn: .constant(index == 0)).toggleStyle(.checkbox).labelsHidden()
                        } else {
                            HelmCheckboxSlot()
                        }
                        Text(verbatim: index == 3 ? Sample.russian : Sample.title).lineLimit(1)
                        Spacer()
                        Text(verbatim: Sample.figure).helmFigure()
                    }
                }
                .helmStripedList(rowPitch: 28)
                .frame(width: 560, height: 190)
                VStack(spacing: HelmSpace.s3) {
                    HelmAppRuleRow(bundleID: Sample.ruleApp) {
                        Toggle(Sample.title, isOn: .constant(true)).labelsHidden()
                    } remove: {}
                    HelmAppRuleRow(bundleID: Sample.title, controls: { Button(Sample.short) {} },
                                   note: { HelmSettingsNote(Sample.russianNote) }, remove: {})
                    HelmAppRuleRow(bundleID: Sample.title) {
                        Toggle(Sample.title, isOn: .constant(false)).labelsHidden()
                    } remove: {}
                    .disabled(true)
                }
                .helmCard()
                .frame(width: 560)
                VStack(alignment: .leading, spacing: HelmSpace.s5) {
                    HelmRemovalOutcome(succeededText: Sample.moved, removed: 3, failures: [])
                    HelmRemovalOutcome(succeededText: Sample.moved, removed: 0, failures: Sample.refusals(1))
                    HelmRemovalOutcome(succeededText: Sample.moved, removed: 2, failures: Sample.refusals(6),
                                       needsFullDiskAccess: true)
                }
                .frame(width: 560)
                .allowsHitTesting(false)
            }
        }
    }
}
