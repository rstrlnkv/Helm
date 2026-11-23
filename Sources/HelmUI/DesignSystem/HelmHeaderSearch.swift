import SwiftUI

/// **The page's search in the header row: a 36 pt capsule holding an unbezeled `NSSearchField`, 283 wide, or, under
/// Always Collapse Search, a 36 pt magnifier while it rests.**
///
/// The capsule is the surface: `HelmSurface.barPlate` under `.flat`, the system's interactive glass in its own
/// container under `.liquidGlass`. `SettingsWindow.minSize` is measured with the open width, on the Log page, in
/// each of the eight languages. Return is the only thing that submits.
/// `sendsWholeSearchString` makes the keystrokes reach the page through the binding alone, and
/// `sendsActionOnEndEditing` off keeps ending the edit (focus moving elsewhere) from firing the action
/// as well; `recentsAutosaveName` nil keeps no history of what was typed.
///
/// **Resting (`rests`).** The field stays mounted, so the binding and what walks the view for it keep working; when
/// it rests it is invisible, out of hit-testing and out of accessibility, and the slot is `HelmHeaderActions.side`
/// wide with a magnifier button on the same capsule, which VoiceOver names as the field is named. A press on it,
/// or ⌘F (which opens and focuses the field on every page with a search, whatever the setting), opens the slot to
/// `width` and focuses the field. It closes again when the editing ends with the field
/// empty (Escape in an empty field, a click elsewhere, focus moving away); a query keeps it open. Only the slot's
/// width moves, by `HelmMotion.interface`, which Reduce Motion cuts.
struct HelmHeaderSearch: View {
    /// The Kit's Search Field (Figma 8:102), the owner's size. The Log page's French prompt, «Rechercher dans le journal», measured with 8 pt to spare in the old 200, so it reads uncut in this width; no other prompt was measured.
    nonisolated static let width: CGFloat = 283

    /// **The one rest predicate.** The search rests as a magnifier only while the setting is on, nobody has opened it
    /// (`isOpen`: a press, ⌘F, or the editor being up) and it holds no query: a query is never hidden behind a glyph.
    nonisolated static func rests(alwaysCollapse: Bool, isOpen: Bool, hasQuery: Bool) -> Bool {
        alwaysCollapse && !isOpen && !hasQuery
    }

    let search: HelmHeaderQuery
    @Environment(\.helmBarAppearance) private var appearance
    @Environment(\.helmHeaderChoices) private var choices
    @State private var isOpen = false
    @State private var focusRequests = 0

    var body: some View {
        let rests = Self.rests(alwaysCollapse: choices.collapseSearch, isOpen: isOpen,
                               hasQuery: !search.text.wrappedValue.isEmpty)
        slot(rests: rests).helmBarCapsule(appearance, glass: .regular.interactive())
    }

    private func slot(rests: Bool) -> some View {
        ZStack(alignment: .leading) {
            HelmHeaderSearchField(search: search, isOpen: $isOpen, focusRequests: $focusRequests,
                                  collapses: choices.collapseSearch, rests: rests)
                .frame(width: Self.width, height: HelmHeaderActions.side)
                .opacity(rests ? 0 : 1)
                .allowsHitTesting(!rests)
                .accessibilityHidden(rests)
            if rests {
                Button {
                    isOpen = true
                    focusRequests += 1
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .imageScale(.large)
                        .frame(width: HelmHeaderActions.side, height: HelmHeaderActions.side)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(HelmA11y.searchField)
                .help(HelmA11y.searchField)
            }
        }
        .frame(width: rests ? HelmHeaderActions.side : Self.width, height: HelmHeaderActions.side, alignment: .leading)
        // The field is wider than the slot while it opens and closes; the mask is the capsule, outset a little
        // when open so the focus ring (drawn outside the field) is not cut.
        .mask { Capsule().padding(rests ? 0 : -8) }
        .animation(HelmMotion.interface, value: rests)
    }
}
