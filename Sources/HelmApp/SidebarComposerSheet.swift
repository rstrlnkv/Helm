import SwiftUI
import AppKit
import HelmRuntime
import HelmUI
import HelmAppStrings

/// Composing the sidebar, in a sheet.
///
/// An editor this size, always open on the page, would outweigh every row
/// around it, and a grouped `Form` cannot hold it without a card inside a
/// card. So the page keeps one row of its own width, which says what is
/// arranged without opening anything, and the row opens this sheet.
struct SidebarComposerSheet: View {
    @ObservedObject var host: ModuleHost
    @Environment(\.dismiss) private var dismiss

    /// Bumped on every write so the sheet redraws from the stored value rather
    /// than from a copy that can drift away from it.
    @State private var revision = 0
    /// Seeded from the arrangement, not from a placeholder: AppKit sizes a
    /// sheet's window at presentation, and the measured height arrives a turn
    /// of the run loop later, so a placeholder would open the sheet cut to its
    /// middle band, title and buttons outside.
    @State private var tableHeight: CGFloat
    /// Measured once, at init: `chromeHeight` builds a hosting controller to
    /// see how the note wraps, and the sheet's body is evaluated on every
    /// keystroke of a rename.
    private let chrome: CGFloat

    init(host: ModuleHost) {
        self.host = host
        self.chrome = Self.chromeHeight
        let layout = SidebarLayoutStore.current()
        _tableHeight = State(initialValue:
            SidebarComposerList.estimatedHeight(of: layout))
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
    /// **`noteHeight` measures this exact value and `body` draws it**, so the
    /// strings, the font and the wrap width cannot disagree: a measurement of a
    /// second declaration would size the sheet for a note nobody sees.
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
    /// **The cap is read from the window, not written down again**, so
    /// changing the window's height moves this with it.
    ///
    /// **A resized window can still be shorter than the sheet, and this does
    /// not know.** `contentMinSize` is lower and the frame is autosaved, so on
    /// a window somebody has made small the sheet hangs below the parent's
    /// bottom edge. The fix is a cap that follows the presenting window, a
    /// larger change kept as its own piece of work.
    ///
    /// The floor is also the answer for a height that is not a number:
    /// `.frame(height:)` is not where a window should find out it has no size,
    /// and the seeded estimate is corrected a turn of the run loop later. A
    /// height that is merely enormous keeps the cap.
    static func windowHeight(table: CGFloat, chrome: CGFloat) -> CGFloat {
        (table + chrome).clamped(to: 360...SettingsWindow.defaultSize.height,
                                 whenNotANumber: 360)
    }

    private var layout: SidebarLayout {
        _ = revision
        return SidebarLayoutStore.current()
    }

    private func apply(_ next: SidebarLayout) {
        SidebarLayoutStore.write(next, to: AppSettings.store)
        // The list is built from `revision`, so this is the transaction every
        // change to the arrangement has to travel in, or the list's measured
        // height jumps in one frame (an `.animation(_, value:)` on the frame
        // does not reach row heights written raw underneath).
        withAnimation(HelmMotion.interface) { revision &+= 1 }
        // The sidebar cannot observe UserDefaults; this is the notification it
        // already listens for. The icon menu reads the store at each right click.
        NotificationCenter.default.post(name: .helmModuleOrderChanged, object: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(AppStr.sidebarSections)
                    // The step `HelmPageHeader` sets a page's own title on: a
                    // sheet's title reads at the same rank.
                    .font(HelmText.plateTitle)
                Spacer()
                Button(HelmWord.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
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
                // The block on the page has a resting state because it sits
                // under things a person came for; a sheet is opened on purpose
                // and by one button, so the list here has none.
                SidebarComposerList(layout: layout, host: host,
                                    height: $tableHeight, apply: apply,
                                    rename: { section in
                                        draftName = AppStr.sectionTitle(section)
                                        renaming = section
                                    })
                    .frame(height: tableHeight)
                    // 20 like the header and the footer, less the 8 pt a plain
                    // `List` insets its own content by. Measured off a
                    // screenshot: a `List` is an AppKit table and draws
                    // nothing offscreen without a window.
                    .padding(.horizontal, 12)
                    // Not symmetric, so that what you see is: the list opens
                    // with a section gap of 10 above its first heading and
                    // closes with 5 under its last row.
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
        // The way out for a keyboard. «Done» holds Return, and there is no
        // Cancel: every edit is applied as it is made, so Escape means «Done».
        .onExitCommand { dismiss() }
        .alert(HelmWord.rename, isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField(HelmWord.rename, text: $draftName)
            Button(HelmWord.done) {
                if let section = renaming { apply(layout.renaming(section.id, to: draftName)) }
                renaming = nil
            }
            Button(HelmWord.cancel, role: .cancel) { renaming = nil }
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
        HelmSettingRow(AppStr.sidebarSections, note: summary) {
            Button(HelmWord.edit) { composing = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .helmModuleOrderChanged)) { _ in
            revision &+= 1
        }
    }

    /// Counted from the arrangement rather than from the registry: a section
    /// somebody emptied is still a section they made.
    private var summary: String {
        _ = revision
        let layout = SidebarLayoutStore.current()
        let ids = layout.sections.flatMap(\.modules)
        let on = ids.filter { id in
            ModuleRegistry.descriptor(id).map { host.isEnabled($0) } ?? false
        }.count
        return AppStr.sidebarSummary(on: on, of: ids.count, sections: layout.sections.count)
    }
}
