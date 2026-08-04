import SwiftUI
import HelmUI

/// The block in Settings where the sidebar is composed: one card per section,
/// a row per module, and every change written the moment it is made.
///
/// **Written on change, not on close.** An arrangement lost because a window
/// was shut is an arrangement nobody makes twice.
///
/// **Two ways to move a module, on purpose.** Dragging reorders inside a
/// section, which is what `.onMove` on a `List` gives for free — the system's
/// own lift, gap and drop. Moving *between* sections is the row's menu rather
/// than a drag across two separate `List`s, which SwiftUI does not make
/// reliable: a drop that sometimes lands is worse than a menu that always does,
/// and the menu is the only one of the two a keyboard can reach.
@MainActor
struct SidebarSettingsSection: View {
    @ObservedObject var host: ModuleHost
    /// Bumped on every write so the block redraws from the stored value rather
    /// than from a copy that can drift away from it.
    @State private var revision = 0
    @State private var renaming: String?
    @State private var draftName = ""

    private var layout: SidebarLayout {
        _ = revision
        return SidebarLayoutStore.read(from: AppSettings.store,
                                       registry: SidebarLayoutStore.registry())
    }

    private func apply(_ change: (SidebarLayout) -> SidebarLayout) {
        SidebarLayoutStore.write(change(layout), to: AppSettings.store)
        revision &+= 1
        // The sidebar and the icon menu read the same value and cannot observe
        // UserDefaults; this is the notification both already listen for.
        NotificationCenter.default.post(name: .helmModuleOrderChanged, object: nil)
    }

    var body: some View {
        Section {
            Text(AppStr.sidebarSectionsNote)
                .font(.caption).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(layout.sections) { section in
                sectionCard(section)
            }
            Button {
                apply { $0.addingSection(named: AppStr.newSection) }
            } label: {
                Label(AppStr.newSection, systemImage: "plus")
            }
        } header: {
            Text(AppStr.sidebarSections)
        }
    }

    // MARK: - One section

    @ViewBuilder
    private func sectionCard(_ section: SidebarLayout.Section) -> some View {
        DisclosureGroup {
            ForEach(section.modules, id: \.self) { id in
                if let descriptor = ModuleRegistry.all.first(where: { $0.idRaw == id }) {
                    moduleRow(descriptor, in: section)
                }
            }
            .onMove { indices, destination in
                move(within: section, from: indices, to: destination)
            }
            if section.modules.isEmpty {
                Text(AppStr.sidebarSectionsNote)
                    .font(.caption2).foregroundStyle(HelmText.faint)
                    .lineLimit(1)
            }
        } label: {
            sectionHeader(section)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ section: SidebarLayout.Section) -> some View {
        HStack(spacing: 8) {
            if renaming == section.id {
                TextField(AppStr.sidebarSections, text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename(section) }
                Button(AppStr.done) { commitRename(section) }
                    .buttonStyle(.borderless)
            } else {
                Text(AppStr.sectionTitle(section)).font(.body.weight(.medium))
                Spacer()
                Menu {
                    Button(AppStr.renameSection) {
                        draftName = AppStr.sectionTitle(section)
                        renaming = section.id
                    }
                    // Only for a section that has a seed to fall back to, and
                    // only when it has been renamed away from it.
                    if section.seed != nil, section.name != nil {
                        Button(AppStr.useDefaultSectionName) {
                            apply { $0.renaming(section.id, to: nil) }
                        }
                    }
                    Divider()
                    Button(AppStr.removeSection, role: .destructive) {
                        apply { $0.removingSection(section.id) }
                    }
                    // The last section holds every module: removing it would
                    // leave them nowhere, so the item is offered and refused
                    // rather than hidden without explanation.
                    .disabled(layout.sections.count == 1)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(HelmA11y.moreActions)
            }
        }
    }

    private func commitRename(_ section: SidebarLayout.Section) {
        apply { $0.renaming(section.id, to: draftName) }
        renaming = nil
    }

    // MARK: - One module

    @ViewBuilder
    private func moduleRow(_ descriptor: any ModuleDescriptor,
                           in section: SidebarLayout.Section) -> some View {
        HStack(spacing: 10) {
            HelmIconPlate(symbol: descriptor.moduleMetadata.sfSymbol,
                          tint: descriptor.moduleTint.colour, size: 20,
                          active: host.isEnabled(descriptor))
            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.moduleMetadata.name)
                Text(descriptor.moduleMetadata.summary)
                    .font(.caption).foregroundStyle(HelmText.quiet)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if layout.sections.count > 1 {
                Menu {
                    ForEach(layout.sections.filter { $0.id != section.id }) { other in
                        Button(AppStr.sectionTitle(other)) {
                            apply { $0.moving(descriptor.idRaw, toSection: other.id, before: nil) }
                        }
                    }
                } label: {
                    Text(AppStr.moveToSection)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Toggle(descriptor.moduleMetadata.name, isOn: Binding(
                get: { host.isEnabled(descriptor) },
                set: { host.setEnabled(descriptor, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        // A disabled module dims in place rather than sinking: sinking costs
        // the position the person chose, and they find out only when they
        // switch it back on.
        .opacity(host.isEnabled(descriptor) ? 1 : 0.55)
    }

    /// `.onMove` speaks in offsets inside the section it was given; the layout
    /// speaks in ids. This is the only translation between the two.
    private func move(within section: SidebarLayout.Section,
                      from indices: IndexSet, to destination: Int) {
        guard let from = indices.first, from < section.modules.count else { return }
        let moved = section.modules[from]
        let before: String? = destination < section.modules.count ? section.modules[destination] : nil
        apply { $0.moving(moved, toSection: section.id, before: before) }
    }
}
