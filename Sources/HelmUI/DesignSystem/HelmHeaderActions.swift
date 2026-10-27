import SwiftUI

/// **The page's actions in the header row: one run of glyph buttons, every declared one's width held.**
///
/// A page shows some of its actions on some of its tabs only (`HelmToolbarAction.isVisible`); the room of
/// every declared one is kept, so the ones that stay do not slide when another comes or goes. Under
/// `.liquidGlass` each button wears the system's glass, joined into one group; under `.flat` the glyphs
/// stand bare. Pressing runs the action's own closure — there is no model between.
///
/// The glyph, its size and its dimming are `HelmToolbarActionsCapsule`'s, the toolbar's own capsule, and the
/// numbers are read from it until that capsule is deleted and they move here.
struct HelmHeaderActions: View {
    let actions: [HelmToolbarAction]

    @Namespace private var glassSpace
    @Environment(\.helmBarAppearance) private var appearance
    @Environment(\.colorScheme) private var colorScheme

    private static let side = HelmToolbarActionsCapsule.side

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                ForEach(actions, id: \.id) { _ in Color.clear.frame(width: Self.side, height: Self.side) }
            }
            .hidden()
            .accessibilityHidden(true)

            GlassEffectContainer(spacing: HelmSpace.s4) {
                HStack(spacing: 0) {
                    ForEach(actions.filter(\.isVisible), id: \.id) { action in
                        backing(control(action).help(action.title).disabled(!action.isEnabled), for: action)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func backing(_ content: some View, for action: HelmToolbarAction) -> some View {
        switch appearance {
        case .liquidGlass:
            content
                .glassEffect(.regular.interactive())
                .glassEffectID(action.id, in: glassSpace)
                .glassEffectUnion(id: "actions", namespace: glassSpace)
        case .flat:
            content
        }
    }

    /// A disabled glyph's own dimming. An inactive window dims the whole row at once (`CardHeader`), so
    /// nothing here answers to it.
    private func opacity(disabled: Bool) -> Double {
        guard disabled else { return 1 }
        return colorScheme == .dark ? HelmToolbarActionsCapsule.disabledGlyphOpacityDark
                                    : HelmToolbarActionsCapsule.disabledGlyphOpacityLight
    }

    private func glyph(_ action: HelmToolbarAction, symbol: String? = nil) -> some View {
        Label(action.title, systemImage: symbol ?? action.symbol)
            .font(.system(size: 13, weight: .medium))
            .imageScale(.large)
            .labelStyle(.iconOnly)
            .helmSteadySpin(action.isBusy)
            .frame(width: Self.side, height: Self.side)
            .contentShape(Rectangle())
            .opacity(opacity(disabled: !action.isEnabled))
    }

    @ViewBuilder
    private func control(_ action: HelmToolbarAction) -> some View {
        switch action.kind {
        case .button(let perform):
            Button(action: perform) { glyph(action) }.buttonStyle(.plain)
        case .toggle(let isOn, let perform):
            if let face = action.toggleFace {
                Button(action: perform) { glyph(action, symbol: face.symbol(isOn: isOn, on: action.symbol)) }
                    .buttonStyle(.plain)
                    .accessibilityValue(face.value(isOn: isOn))
            } else {
                Button(action: perform) {
                    if isOn { glyph(action).foregroundStyle(Color.accentColor) } else { glyph(action) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        case .menu(let items):
            Menu {
                ForEach(items, id: \.id) { item in
                    Toggle(item.title, isOn: Binding(get: { item.isOn }, set: { _ in item.perform() }))
                        .disabled(!item.isEnabled)
                }
            } label: {
                glyph(action)
            }
            .menuIndicator(.hidden)
            // `.menuStyle(.button)` drops the pull-down bezel, which would make a menu wider than the 36 pt
            // every other action takes and so than the room held for it.
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }
}
