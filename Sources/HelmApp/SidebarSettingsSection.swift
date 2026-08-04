import SwiftUI
import HelmUI

/// The block in Settings where the sidebar is composed.
///
/// **The list is an `NSTableView`, not a SwiftUI `List`.** `.onMove` is scoped
/// to one `ForEach`, so a `List` of sections can reorder inside a section and
/// cannot move anything between two. The table gives the system's own drag over
/// the whole thing: a lift, an insertion indicator between any two rows, and a
/// drop that animates — across section boundaries included. Its rows are still
/// SwiftUI, so the plate and the switch are the ones the rest of the app uses.
///
/// **Written on change, not on close.** An arrangement lost because a window
/// was shut is an arrangement nobody makes twice.
@MainActor
struct SidebarSettingsSection: View {
    @ObservedObject var host: ModuleHost
    /// Bumped on every write so the block redraws from the stored value rather
    /// than from a copy that can drift away from it.
    @State private var revision = 0
    /// Reported by the table after it lays out. A table inside a `Form` must
    /// not scroll — the page already does — so it is given exactly the height
    /// its rows came to.
    @State private var tableHeight: CGFloat = 200
    @State private var renaming: SidebarLayout.Section?
    @State private var draftName = ""

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
        // **The whole block is the section's header, and its content is empty.**
        // The redesign puts a card on each sidebar section; a grouped `Form`
        // section draws a card of its own around whatever it holds, and the two
        // together are a card inside a card — measured on the shipped build at
        // L 0.87137 inside L 0.93011 where the page is 1.0, a nesting that
        // appears nowhere else in Helm.
        //
        // A header is the one part of a `Form` section macOS draws *outside*
        // that card. Rendered all four candidates side by side before choosing:
        // a plain section, `.listRowBackground(.clear)` on the content, the same
        // on the `Section`, and this. The first three are pixel-identical — in a
        // macOS grouped `Form`, `listRowBackground` does nothing at all.
        Section {
            EmptyView()
        } header: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    // Restated, because the reset below strips what a header
                    // would have given it. Matched to the sections either side.
                    Text(AppStr.sidebarSections)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(AppStr.restoreSections) {
                        apply(SidebarLayout.seeded(from: SidebarLayoutStore.registry()))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                }
                // Above the list, not under it. It says what the list is for,
                // which is something to read *before* dragging rather than a
                // note explaining what just happened.
                Text(AppStr.sidebarSectionsNote)
                    .font(.system(size: 11))
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)

                SidebarComposerTable(layout: layout, host: host,
                                     height: $tableHeight, apply: apply,
                                     rename: { section in
                                         draftName = AppStr.sectionTitle(section)
                                         renaming = section
                                     })
                    .frame(height: tableHeight)
                    .padding(.top, 2)
                    // A `Form` header is inset 10 pt further than the cards it
                    // introduces — measured on this page, the system's card
                    // edges are 540 and 1940 where the header's are 560 and
                    // 1920. The heading text wants that inset; the section
                    // cards want to line up with the cards above and below
                    // them, so the table takes it back.
                    .padding(.horizontal, -10)

                Button {
                    apply(layout.addingSection(named: AppStr.newSection))
                } label: {
                    Label(AppStr.newSection, systemImage: "plus")
                        .font(.system(size: 12))
                        .padding(.top, 4)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            // A header sets its own weight and colour on everything inside it,
            // so a row's name came out bold. Reset once here rather than at
            // every leaf; the parts that want something else still say so.
            .font(.system(size: 13))
            .fontWeight(.regular)
            .foregroundStyle(.primary)
            .textCase(nil)
            // A header carries no gap to whatever the form draws next, because
            // normally a card does. There is no card here.
            .padding(.bottom, 14)
        }
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
