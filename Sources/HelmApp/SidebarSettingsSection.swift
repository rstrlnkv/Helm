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
    /// Two states, not one list with controls in it. At rest the block is a
    /// list of what the sidebar holds; in edit it grows the note, the grips,
    /// the section menus and the row of buttons that change the arrangement.
    /// **The rows themselves are the same height in both** — the mode changes
    /// what a row contains, never how tall it is, so nothing below the block
    /// moves except by the note and that one row of buttons. Every switch stays
    /// live in both: turning a module off is not rearranging it.
    @State private var editing = false
    /// Natural sizes of the parts only edit mode has, recorded while they are
    /// on screen so they can be revealed by growing to them rather than by
    /// fading in. A fade let the note draw on top of what was already there
    /// (ARCHITECTURE.md § Motion).
    @State private var noteHeight: CGFloat = 0
    /// The height of the row of edit-mode buttons under the list.
    @State private var actionsHeight: CGFloat = 0

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
            // `spacing: 0`, with every gap written as padding on the thing
            // above it. A collapsed reveal is a view of zero height, and a
            // stack with spacing still puts its gap on both sides of one —
            // so the block would keep 12 pt of air at rest for two things
            // that are not there.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    // Restated, because the reset below strips what a header
                    // would have given it. Matched to the sections either side.
                    Text(AppStr.sidebarSections)
                        .font(HelmText.sectionHeading)
                    Spacer(minLength: 8)
                    // The one control that is here in both states, so it is the
                    // one that is drawn as a button. The other two belong to
                    // edit mode and live at the foot of the list with it.
                    Button {
                        withAnimation(HelmMotion.interface) { editing.toggle() }
                    } label: {
                        // A cut, not a cross-fade. One word replacing another
                        // over 300 ms is the two of them legible through each
                        // other in the middle — photographed as «ИЗмОетНоИвТЬ»
                        // — and there is nothing here that needs to travel:
                        // the button does not move, only its word changes.
                        Text(editing ? AppStr.done : AppStr.edit)
                            .contentTransition(.identity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Above the list, not under it. It says what the list is for,
                // which is something to read *before* dragging rather than a
                // note explaining what just happened — and only while it is
                // true: "drag to reorder" over a list nothing drags is an
                // instruction that fails when followed.
                Text(AppStr.sidebarSectionsNote)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                        if height > 0 { noteHeight = height }
                    }
                    .frame(height: editing ? noteHeight : 0, alignment: .top)
                    .clipped()
                    .accessibilityHidden(!editing)

                SidebarComposerList(layout: layout, host: host, editing: editing,
                                    height: $tableHeight, apply: apply,
                                    rename: { section in
                                        draftName = AppStr.sectionTitle(section)
                                        renaming = section
                                    })
                    .frame(height: tableHeight)
                    .padding(.top, 8)
                    // A `Form` header is inset 10 pt further than the cards it
                    // introduces — measured on this page, the system's card
                    // edges are 540 and 1940 where the header's are 560 and
                    // 1920. The heading text wants that inset; the section
                    // cards want to line up with the cards above and below
                    // them, so the table takes it back.
                    .padding(.horizontal, -10)

                // **Both of edit mode's actions, on one row under the list.**
                // "Restore defaults" used to sit in the heading beside Edit,
                // where it had to appear out of nothing next to a button that
                // was already there. Down here it arrives with the row it
                // belongs to: one thing grows, and the two buttons are inside
                // it — adding a section on the left, undoing every arrangement
                // on the right, as far from each other as the row allows.
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
                .padding(.top, 10)
                .padding(.horizontal, 4)
                // Its own size regardless of what the collapsed frame proposes,
                // or the thing being measured is the measurement.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    if height > 0 { actionsHeight = height }
                }
                .frame(height: editing ? actionsHeight : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(editing)
                .accessibilityHidden(!editing)
            }
            // A header sets its own weight and colour on everything inside it,
            // so a row's name came out bold. Reset once here rather than at
            // every leaf; the parts that want something else still say so.
            .font(HelmText.rowTitle)
            .fontWeight(.regular)
            .foregroundStyle(.primary)
            .textCase(nil)
            // A header carries no gap to whatever the form draws next, because
            // normally a card does. There is no card here.
            //
            // **24, not 14: the last card needs the air the others get.** Inside
            // the list a section's card is followed by the next section's
            // heading, which brings 29 pt of its own. The last card has nothing
            // after it but the next block of the page, and at 14 pt it read as
            // cut off rather than finished — reported as "Клавиатура обрезается"
            // and measured as a row of exactly its full height, flush against
            // whatever the form drew next.
            .padding(.bottom, 24)
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
