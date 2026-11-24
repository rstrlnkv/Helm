import SwiftUI
import HelmRuntime
import HelmUI
import HelmAppStrings

// The panel's chrome and its two standing tiles, drawn by the card in
// `HelmPanel.swift`. Internal rather than `private` for that reason and no
// other: nothing outside `HelmApp` names any of them.

/// What a widget grows while the panel is being arranged: a minus at the top
/// left, and its proportions — or, on the drawer, a pencil — at the top right.
///
/// **Both float at the corners, half outside the tile**, where macOS puts
/// «remove» on a jiggling icon: the corner of a card is the one place a module
/// never draws anything, so a control parked there covers nothing.
///
/// **The size control is one chip until you point at it.** Three chips on
/// every tile would compete with the tile on a panel meant to be read at a
/// glance; one chip says what the size is. It opens on hover and on focus, so
/// a keyboard can reach it.
struct EditChrome: ViewModifier {
    let active: Bool
    let size: PanelWidgetSize
    let sizes: [PanelWidgetSize]
    /// This tile is the one being carried, so it is a slot: no content, and no
    /// controls hanging off a corner that has nothing behind it.
    let lifted: Bool
    /// The slot's grey well — on its own flag, not on `lifted`, because it
    /// outlives the drag and fades after the exact handover.
    let wellVisible: Bool
    /// The mode is arrangement, not use: a clear layer over the tile's own
    /// controls, so a drag can start anywhere on it (a working toggle would
    /// claim the mouse-down). The chrome sits above the shield and stays
    /// pressable.
    let shielded: Bool

    /// Non-nil for a widget whose corner control chooses something other than a
    /// size — the drawer, which chooses its rows.
    let choose: (() -> Void)?
    let choosing: Bool
    let resize: (PanelWidgetSize) -> Void
    let remove: () -> Void
    let move: (Int) -> Void

    /// How far the corner controls overhang a tile, and so what the tile is padded by while the mode is on.
    /// The drag (`HelmPanelContent.gridDrag`, `HelmPanel.swift`) insets each measured frame by it to get the tile's content rectangle.
    static let overhang = HelmSpace.s2

    @Environment(\.helmTraits) private var traits
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var open: Bool { hovering || focused }

    /// Named once so the glyph and the swap cannot disagree about which symbol
    /// is on screen. The pair shares nothing, so the swap always takes Magic
    /// Replace's fallback.
    private var chooseSymbol: String { choosing ? "checkmark" : "pencil" }

    func body(content: Content) -> some View {
        // **One branch, whatever the mode.** An `if` on the mode would be two
        // identities to SwiftUI: entering the mode would rebuild every tile,
        // leaving nothing to interpolate, and the grid would snap.
        content
            // The slot of a tile that is being carried: the content steps
            // aside, a quiet well marks the place, and the overlay above the
            // grid is the one full-weight copy under the pointer.
            .opacity(lifted ? 0 : 1)
            .background {
                // Opacity, not insertion: a transition's animation is whatever
                // transaction happens to be running. A plain opacity is
                // governed by its scoped animation, always, including at the
                // drop, where the content above it swaps with animations off.
                RoundedRectangle(cornerRadius: HelmRadius.frame, style: .continuous)
                    .fill(HelmSurface.wellFill)
                    .opacity(wellVisible ? 1 : 0)
                    .animation(HelmMotion.wellFade, value: wellVisible)
            }
            // Slow on purpose, slower than the hand. Both durations and their
            // reasons live on `HelmMotion.slotFade` / `.wellFade`.
            .animation(HelmMotion.slotFade, value: lifted)
            .overlay {
                if shielded {
                    Color.clear.contentShape(RoundedRectangle(cornerRadius: HelmRadius.frame, style: .continuous))
                }
            }
            .overlay(alignment: .topLeading) {
                if active, !lifted {
                    Button {
                        remove()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(HelmText.onFill)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(HelmSignal.danger(increased: traits.increasedContrast)))
                            .shadow(radius: 1, y: 0.5)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -Self.overhang, y: -Self.overhang)
                    .accessibilityLabel(AppStr.removeWidget)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                Group {
                    if !active || lifted {
                        EmptyView()
                    } else if let choose {
                        Button(action: choose) {
                            Image(systemName: chooseSymbol)
                                .helmSymbolSwap(chooseSymbol)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(choosing ? HelmText.onFill : HelmText.quiet)
                                .padding(.horizontal, HelmSpace.s3).padding(.vertical, 3)
                                .helmPillTrack(choosing ? AnyShapeStyle(Color.accentColor)
                                                        : AnyShapeStyle(.regularMaterial))
                        }
                        .buttonStyle(.plain)
                        .help(AppStr.chooseUtilities)
                        .accessibilityLabel(AppStr.chooseUtilities)
                    } else {
                        sizeControl
                    }
                }
                .offset(x: Self.overhang, y: -Self.overhang)
                .transition(.scale.combined(with: .opacity))
            }
            // The room the corner controls overhang by, exactly: the grid
            // lives in a `ScrollView`, which clips at its own bounds. Animated
            // by the mode's own transaction, since it is part of what the mode
            // changes.
            .padding(active ? Self.overhang : 0)
            // Movable by arrow keys, so a keyboard can arrange the panel too.
            // No system ring: it is drawn round the frame, a hard rectangle
            // over glass.
            .focusable(active)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                guard active else { return }
                switch direction {
                case .left, .up: move(-1)
                case .right, .down: move(1)
                default: break
                }
            }
    }

    /// Grows leftwards from the corner it is anchored to, which is what a
    /// trailing-aligned stack does by itself.
    private var sizeControl: some View {
        HStack(spacing: HelmSpace.s1) {
            ForEach(open ? sizes : [size], id: \.self) { option in
                Button {
                    // Shut on the way out, and say so before the resize: the
                    // tile changes shape under the pointer, so `onHover(false)`
                    // never arrives, and a click leaves the button focused,
                    // the other half of «open».
                    hovering = false
                    focused = false
                    resize(option)
                } label: {
                    // The accent marks which of the three, so it appears only
                    // when there are three. Closed, a blue pill on every tile
                    // would be the loudest thing in the panel.
                    Text(option.label)
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(open && option == size ? HelmText.onFill
                                         : HelmText.quiet)
                        .padding(.horizontal, 5).padding(.vertical, HelmSpace.s1)
                        // A capsule inside a capsule: a capsule's radius is half
                        // its own height, so the two stay concentric whatever
                        // the type size does to them.
                        .background(Capsule()
                            .fill(open && option == size ? Color.accentColor : .clear))
                }
                .buttonStyle(.plain)
                .help(option.label)
            }
        }
        .padding(HelmSpace.s1)
        .helmPillTrack()
        .focusable()
        .focused($focused)
        // The system ring is drawn round the view's frame, a rectangle around
        // a pill. Turned off rather than reshaped, because this control shows
        // its focus by opening, the same signal a pointer gets.
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(HelmMotion.interface, value: open)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppStr.widgetSize)
    }
}

/// One collapsed row listing the modules whose UI lives in Settings. Expanding
/// reveals compact rows; clicking one opens Settings on that module.
struct UtilitiesSection: View {
    let modules: [ModuleHost.Live]
    @Binding var expanded: Bool
    /// The drawer is arranged like everything else in the panel: while the mode
    /// is on, every row offers a way out. It is also held open — a list you
    /// have to disclose before you can edit it is a list nobody edits.
    let editing: Bool
    /// The pencil is pressed: every row is a choice rather than a shortcut.
    let choosing: Bool
    let isOn: (String) -> Bool
    let toggle: (String) -> Void
    private var open: Bool { expanded || editing }
    /// Natural height of the rows, measured so the disclosure animates between
    /// 0 and a concrete value. `nil` until the first measurement lands.
    @State private var rowsHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(HelmMotion.disclosure) { expanded.toggle() }
            } label: {
                HStack(spacing: HelmSpace.s4) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HelmText.quiet)
                    Text(AppStr.utilities).font(.subheadline.weight(.medium))
                    Spacer()
                    // `.caption`: one of the small styles the panel keeps for itself,
                    // beside the `HelmText` faces its rows share with the settings
                    // window (Architecture/TheMenuBarPanel.md).
                    Text("\(modules.count)").font(.caption).foregroundStyle(HelmText.faint)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HelmText.faint)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A bare `.accessibilityLabel` replaces the label SwiftUI
            // synthesizes from the row, so the count goes back as the value,
            // where a number belongs, and the open/closed state with it.
            .accessibilityLabel(AppStr.utilities)
            .accessibilityValue("\(Count(modules.count)), \(HelmA11y.expanded(open))")

            // Measured height rather than `if expanded`: removed rows keep
            // drawing over what sits below while the card's background
            // collapses at once. `helmAccordion` holds the reasons.
            VStack(spacing: HelmSpace.s1) {
                ForEach(modules, id: \.descriptor.idRaw) { live in
                    HStack(spacing: HelmSpace.s3) {
                        utilityRow(live)
                        if choosing {
                            Button { toggle(live.descriptor.idRaw) } label: {
                                Image(systemName: isOn(live.descriptor.idRaw)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(isOn(live.descriptor.idRaw)
                                                     ? Color.accentColor : HelmText.faint)
                            }
                            .buttonStyle(.plain)
                            // The tick is the whole face of this control: the
                            // module is its name, and the tick is the
                            // selection, in the system's own word.
                            .accessibilityLabel(live.descriptor.moduleMetadata.shortName)
                            .accessibilityAddTraits(isOn(live.descriptor.idRaw) ? .isSelected : [])
                        }
                    }
                }
            }
            .padding(.top, HelmSpace.s4)
            // **The one site where the measurement half is load-bearing**: the
            // pencil swaps a few rows for many, so the height changes while
            // the block is open and has to be seen changing.
            .helmAccordion(open: open, height: $rowsHeight)
        }
        .helmPanelCard()
    }

    private func utilityRow(_ live: ModuleHost.Live) -> some View {
        let meta = live.descriptor.moduleMetadata
        return Button {
            NotificationCenter.default.post(name: .helmOpenSettings, object: live.descriptor.idRaw)
        } label: {
            HStack(spacing: HelmSpace.s4) {
                HelmIconPlate(symbol: meta.sfSymbol,
                              tint: live.descriptor.moduleTint.colour, size: 20)
                // The short name, as the sidebar asks for: this column is
                // fixed and «Объекты входа и расширения» is cut mid-word in it.
                // `.callout` is 12, which is off the settings scale: the
                // panel's own type, beside .caption and .subheadline.
                Text(meta.shortName).font(.callout).lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(HelmText.faint)
                    // Decoration: the row is a button and the arrow only
                    // repeats «opens elsewhere».
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The notice that arrives by itself: macOS is withholding something, and
/// these modules are the ones it reaches.
///
/// Not removable, and it is not in the layout at all. Storing it would mean
/// writing a row that has to be deleted the moment somebody presses Grant —
/// and deciding, on every read, whether an absent one was taken off or never
/// added. It is a fact about the machine, so it is computed from the machine.
struct PermissionsWidget: View {
    let withheld: [PermissionNeed]
    // No module count (`AppStr.permissionsWithheld(count:)` says why).

    /// **The banner is the plate**, not inside `HelmWidgetBody`: the banner
    /// draws a filled field of its own, and a panel card around it would be a
    /// card inside a card. One sentence and one button, so it takes the row's
    /// whole width like any 2×1 and only the height it needs.
    var body: some View {
        // `HelmBanner`, the same field as `HelmPermissionNote` in the settings
        // window: one statement, one appearance.
        HelmBanner(AppStr.permissionsWithheld(count: withheld.count),
                   symbol: "exclamationmark.circle.fill", compact: true) {
                // One withheld grant has one place to go, so go there. Several
                // do not, and a button that picks one of them silently is a
                // button that lies about what it opened.
                if withheld.count == 1, let only = withheld.first {
                    Button(HelmWord.grant) { only.openSettings() }
                        .controlSize(.small)
                        .fixedSize()
                } else {
                    Button(AppStr.showPermissions) {
                        NotificationCenter.default.post(name: .helmOpenSettings,
                                                        object: SettingsWindow.settingsPage)
                    }
                    .controlSize(.small)
                    .fixedSize()
                }
            }
    }
}

/// The tile of a module that is switched off.
///
/// It keeps its place: switching a module off is not a request to rearrange
/// the panel. The plate is drawn inactive, and the one button is the way back.
struct DisabledModuleWidget: View {
    let descriptor: any ModuleDescriptor

    var body: some View {
        HelmWidgetBody {
            HStack(spacing: HelmSpace.s4) {
                HelmIconPlate(symbol: descriptor.moduleMetadata.sfSymbol,
                              tint: descriptor.moduleTint.colour, size: 18, active: false)
                Text(descriptor.moduleMetadata.shortName)
                    .font(HelmText.rowTitle.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            Text(AppStr.moduleIsOff)
                .helmQuietDetail()
            Button(HelmWord.turnOn) {
                ModuleHost.shared.setEnabled(descriptor, true)
                NotificationCenter.default.post(name: .helmModuleOrderChanged, object: nil)
            }
            .controlSize(.small)
        }
    }
}
