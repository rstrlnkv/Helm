import SwiftUI
import HelmUI
import HelmRuntime

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
    @State private var tableHeight: CGFloat = 200
    @State private var renaming: SidebarLayout.Section?
    @State private var draftName = ""

    /// Everything the sheet draws that is not the list: the title row, the
    /// note, two dividers, the actions row and the padding around them.
    /// Measured off the shipped sheet at 2x — 126 pt — plus the 29 the scroll
    /// view puts above and below its content.
    private static let chromeHeight: CGFloat = 155

    private var layout: SidebarLayout {
        _ = revision
        return SidebarLayoutStore.read(from: AppSettings.store,
                                       registry: SidebarLayoutStore.registry())
    }

    private func apply(_ next: SidebarLayout) {
        SidebarLayoutStore.write(next, to: AppSettings.store)
        revision &+= 1
        // The sidebar and the icon menu read the same value and cannot observe
        // UserDefaults; this is the notification both already listen for.
        NotificationCenter.default.post(name: .helmModuleOrderChanged, object: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(AppStr.sidebarSections)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(AppStr.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Text(AppStr.sidebarComposerNote)
                .font(.caption)
                .foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        // Sized to the arrangement, up to a cap. The cap is what the nine
        // modules and four sections Helm ships with need — 485 pt of list —
        // so the standard arrangement never scrolls; a person who makes more
        // sections than that gets a scroll bar rather than a sheet taller than
        // the window it sits in.
        .frame(width: 460,
               height: min(max(360, tableHeight + Self.chromeHeight), 660))
        .alert(AppStr.renameSection, isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField(AppStr.sidebarSections, text: $draftName)
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
        LabeledContent {
            Button(AppStr.edit) { composing = true }
        } label: {
            Text(AppStr.sidebarSections)
            Text(summary)
                .font(.caption)
                .foregroundStyle(HelmText.quiet)
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
        let modules = layout.sections.reduce(0) { $0 + $1.modules.count }
        return AppStr.sidebarSummary(modules: modules, sections: layout.sections.count)
    }
}
