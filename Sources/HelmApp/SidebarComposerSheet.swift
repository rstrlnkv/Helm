import SwiftUI
import AppKit
import HelmRuntime
import HelmUI

/// Composing the sidebar, in a sheet.
///
/// It used to be the page's largest block by a distance — ten module rows and
/// their headings, always open, under four settings rows. And it did not line
/// up with them: a grouped `Form` draws a card around a section's *content*
/// and leaves its *header* outside, and the block was written as a header on
/// purpose, to avoid a card inside a card. The price was a block 10 pt wider
/// than everything above and below it.
///
/// A row that opens a sheet fixes both, and it is what the mockups say to do
/// with an editor. The page keeps one row of its own width, which says what
/// is arranged without opening anything.
struct SidebarComposerSheet: View {
    @ObservedObject var host: ModuleHost
    @Environment(\.dismiss) private var dismiss

    /// Bumped on every write so the sheet redraws from the stored value rather
    /// than from a copy that can drift away from it.
    @State private var revision = 0
    /// Seeded from the arrangement, not from a placeholder.
    ///
    /// This started at a flat 200. A sheet's window is sized by AppKit at
    /// presentation, and the measured height arrives a turn of the run loop
    /// later — so the window took `200 + chrome`, clamped up to the 360 pt
    /// floor, while the content asked for 631. What you saw was the middle
    /// band of the sheet: no title, no «Готово», no footer buttons, the last
    /// two modules below the window's edge, and Escape the only way out that
    /// nothing on screen mentioned.
    @State private var tableHeight: CGFloat
    /// Measured once, at init: `chromeHeight` builds a hosting controller to
    /// see how the note wraps, and the sheet's body is evaluated on every
    /// keystroke of a rename.
    private let chrome: CGFloat

    init(host: ModuleHost) {
        self.host = host
        self.chrome = Self.chromeHeight
        let layout = SidebarLayoutStore.read(from: AppSettings.store,
                                             registry: SidebarLayoutStore.registry())
        _tableHeight = State(initialValue:
            SidebarComposerList.estimatedHeight(of: layout, editing: true))
    }

    @State private var renaming: SidebarLayout.Section?
    @State private var draftName = ""

    /// Everything the sheet draws that is not the list and not the note: the
    /// title row, two dividers, the actions row, the padding around them, and
    /// the 29 pt the scroll view puts above and below its content. Measured off
    /// the shipped sheet at 2x.
    private static let fixedChrome: CGFloat = 129
    /// The sheet's width, and the note's, less the 20 pt gutter on each side.
    static let width: CGFloat = 460

    /// The gutter the note is drawn inside, and therefore the width it wraps
    /// at. Named because two places need the same number and one of them needs
    /// it doubled.
    private static let noteGutter: CGFloat = 20

    /// The note itself — the sentence and the font, declared once.
    ///
    /// **`noteHeight` measures this exact value and `body` draws it.** They
    /// used to spell it out separately: the same two strings joined the same
    /// way, the same `.font`, and the wrap width as `width - 40` here against
    /// `.padding(.horizontal, 20)` there. Three things that had to agree, in
    /// two places, with nothing to make them.
    ///
    /// That is the defect below one level in. The height was a constant once,
    /// and it went stale twice in an afternoon — the note wrapped differently,
    /// then the font moved from `.caption` to `HelmText.rowDetail` — so it was
    /// replaced by a measurement. But a measurement of a *second declaration*
    /// can go stale the same way: change the font where it is drawn and the
    /// sheet is sized for a note nobody sees.
    private static var note: Text {
        Text(AppStr.sidebarComposerNote + " " + AppStr.moduleSwitchNote)
            .font(HelmText.rowDetail)
    }

    /// Measured rather than guessed. `sizeThatFits` sees wrapping, which is
    /// exactly what a constant could not, and it answers for whichever language
    /// is actually running.
    private static var noteHeight: CGFloat {
        NSHostingController(rootView: note.fixedSize(horizontal: false, vertical: true))
            .sizeThatFits(in: CGSize(width: Self.width - Self.noteGutter * 2,
                                     height: .greatestFiniteMagnitude))
            .height
    }

    static var chromeHeight: CGFloat { fixedChrome + noteHeight }

    /// Sized to the arrangement, up to the settings window's own content
    /// height. The arrangement Helm ships with fits under it, so the standard
    /// sidebar never scrolls; a person who makes more sections than that gets a
    /// scroll bar rather than a sheet that keeps growing.
    ///
    /// **The cap is read from the window, not written down again.** It was a
    /// literal 660 beside `SettingsWindow`'s literal 700 and a comment saying
    /// the two agreed — and they did not: the tenth module added a 40 pt row,
    /// the shipped arrangement asked for 683, and the composer Helm ships with
    /// came up scrolling. Anyone changing the window's height now moves this
    /// with it. `SidebarComposerHeightTests` measures the shipped arrangement
    /// against its own literal, so the guard still has two sides.
    ///
    /// **A resized window can still be shorter than the sheet, and this does
    /// not know.** `contentMinSize` is 540 and the frame is autosaved, so on a
    /// window somebody has made small the sheet hangs below the parent's bottom
    /// edge — 160 pt at worst, where it was 120 before. The fix is a cap that
    /// follows the *presenting* window rather than the default size, which is a
    /// larger change than a constant and is written down as its own piece of
    /// work rather than half-done here.
    ///
    /// The floor is also the answer for a height that is not a number, which is
    /// what this line gave as `min(max(360, table + chrome), 660)` —
    /// `Swift.max(360, .nan)` is 360 — and the shared clamp hands the NaN back
    /// instead. `.frame(height:)` is not where a window should find out it has
    /// no size, and the floor is where this sheet opens whenever it does not
    /// yet know its content: the seeded estimate is corrected upward a turn of
    /// the run loop later. A height that is merely enormous keeps the cap,
    /// which is what a cap is for.
    static func windowHeight(table: CGFloat, chrome: CGFloat) -> CGFloat {
        (table + chrome).clamped(to: 360...SettingsWindow.defaultSize.height,
                                 whenNotANumber: 360)
    }

    private var layout: SidebarLayout {
        _ = revision
        return SidebarLayoutStore.read(from: AppSettings.store,
                                       registry: SidebarLayoutStore.registry())
    }

    private func apply(_ next: SidebarLayout) {
        SidebarLayoutStore.write(next, to: AppSettings.store)
        // The list is built from `revision`, so this is the transaction every
        // change to the arrangement has to travel in. Without it the list's
        // measured height went from 476 to 536 in one frame — the variant
        // `DisclosureProbe` already proved dead, with `.animation(_, value:)`
        // sitting on the frame and the row heights written raw underneath.
        withAnimation(HelmMotion.interface) { revision &+= 1 }
        // The sidebar and the icon menu read the same value and cannot observe
        // UserDefaults; this is the notification both already listen for.
        NotificationCenter.default.post(name: .helmModuleOrderChanged, object: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(AppStr.sidebarSections)
                    // 16, the scale's step above body, and the same one
                    // `HelmPageHeader` sets a page's own title on — this is a
                    // sheet's title and reads at the same rank. It was 15,
                    // which is on no step and was invisible only because the
                    // ratchet did not read the app shell.
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(AppStr.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, HelmLayout.formInset)
            .padding(.top, 18)
            .padding(.bottom, HelmSpace.s5)

            // The same `note` `noteHeight` measures — the sheet's window is
            // sized from it, so the two must be one value.
            Self.note
                .foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Self.noteGutter)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                // Always editing. The block on the page had a resting state
                // because it sat under things a person came for; a sheet is
                // opened on purpose and by one button, so arriving in a mode
                // that has to be switched on is a click that asks nothing.
                SidebarComposerList(layout: layout, host: host, editing: true,
                                    height: $tableHeight, apply: apply,
                                    rename: { section in
                                        draftName = AppStr.sectionTitle(section)
                                        renaming = section
                                    })
                    .frame(height: tableHeight)
                    // 20 like the header and the footer, less the 8 pt a plain
                    // `List` insets its own content by. Measured off a
                    // screenshot at 2x rather than offscreen: a `List` is an
                    // AppKit table and draws nothing without a window, so the
                    // probe that would have measured it returned an empty
                    // bitmap. Header at 20, cards at 28.5.
                    .padding(.horizontal, 12)
                    // Not symmetric, so that what you see is. The list opens
                    // with a section gap of 10 above its first heading and
                    // closes with 5 under its last row, so equal padding here
                    // produced 20 above and 15 below.
                    .padding(.top, 12)
                    .padding(.bottom, 17)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    apply(layout.addingSection(named: AppStr.newSection))
                } label: {
                    Label(AppStr.newSection, systemImage: "plus")
                }
                Spacer(minLength: 8)
                Button(AppStr.restoreSections) {
                    apply(SidebarLayout.seeded(from: SidebarLayoutStore.registry()))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, HelmLayout.formInset)
            .padding(.vertical, 12)
        }
        .frame(width: Self.width, height: Self.windowHeight(table: tableHeight, chrome: chrome))
        .alert(AppStr.renameSection, isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField(AppStr.renameSection, text: $draftName)
            Button(AppStr.done) {
                if let section = renaming { apply(layout.renaming(section.id, to: draftName)) }
                renaming = nil
            }
            Button(AppStr.cancel, role: .cancel) { renaming = nil }
        }
    }
}

/// The one row the page keeps: what is arranged, and the way in.
struct SidebarComposerRow: View {
    @ObservedObject var host: ModuleHost
    @Binding var composing: Bool
    /// Re-read on the notification the sheet posts: the arrangement lives in
    /// `UserDefaults`, which SwiftUI cannot watch.
    @State private var revision = 0

    var body: some View {
        // Built by hand rather than as a `LabeledContent`. That control aligns
        // its two halves on the label's *first* baseline, which is right for a
        // one-line label and a switch; with a summary underneath it parked the
        // button against the title and left the second line hanging below it.
        //
        // A `LabeledContentStyle` cannot fix it either — `configuration.label`
        // hands the two `Text`s over as one opaque view, and outside the
        // default style they lay themselves out side by side.
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppStr.sidebarSections)
                Text(summary)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
            }
            // A minimum, not a bare `Spacer`: at a narrow width the summary
            // would otherwise run into the button.
            Spacer(minLength: 12)
            Button(AppStr.edit) { composing = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .helmModuleOrderChanged)) { _ in
            revision &+= 1
        }
    }

    /// Counted from the arrangement rather than from the registry: a section
    /// somebody emptied is still a section they made, and the row saying «4»
    /// when the sheet shows four is the point of having a summary at all.
    private var summary: String {
        _ = revision
        let layout = SidebarLayoutStore.read(from: AppSettings.store,
                                             registry: SidebarLayoutStore.registry())
        let ids = layout.sections.flatMap(\.modules)
        let on = ids.filter { id in
            ModuleRegistry.all.first { $0.idRaw == id }.map { host.isEnabled($0) } ?? false
        }.count
        return AppStr.sidebarSummary(on: on, of: ids.count, sections: layout.sections.count)
    }
}
