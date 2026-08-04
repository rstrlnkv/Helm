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
        Section {
            // Table and footer in one card, the way a system list carries its
            // add button attached to the list rather than loose beneath it.
            VStack(spacing: 0) {
                SidebarComposerTable(layout: layout, host: host,
                                     height: $tableHeight, apply: apply,
                                     rename: { section in
                                         draftName = AppStr.sectionTitle(section)
                                         renaming = section
                                     })
                    .frame(height: tableHeight)
                    .padding(.vertical, 2)

                Rectangle().fill(HelmSurface.hairline).frame(height: 1)

                HStack(spacing: 0) {
                    Button {
                        apply(layout.addingSection(named: AppStr.newSection))
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 24, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(AppStr.newSection)
                    .accessibilityLabel(AppStr.newSection)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .background(
                RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
                    .fill(HelmSurface.cardFill)
            )
            .listRowInsets(EdgeInsets())
        } header: {
            Text(AppStr.sidebarSections)
        } footer: {
            // Under the group, not inside it. A sentence explaining a list is
            // not a row of that list, and a card of its own put two cards where
            // the form has one section.
            Text(AppStr.sidebarSectionsNote)
                .font(.caption).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
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
