import SwiftUI
import HelmRuntime
import HelmUI

// The panel's chrome and its two standing tiles, drawn by the card in
// `HelmPanel.swift`. Internal rather than `private` for that reason and no
// other: nothing outside `HelmApp` names any of them.

/// What a widget grows while the panel is being arranged: a dashed frame, a
/// minus at the top left, and its proportions at the top right.
///
/// **Both float at the corners, half outside the tile.** That is where macOS
/// has put «remove» since the first jiggling icon, and the reason it works is
/// the reason it is not an overlay *on* the content: the corner of a card is
/// the one place a module never draws anything, so a control parked there
/// costs nothing. An earlier version put the chips inside the tile's
/// bottom-right corner instead and they landed on the VPN switch, Keep Awake's
/// «⋯» and the Disk widget's used-of-total.
///
/// **The size control is one chip until you point at it.** Three chips on
/// every tile is a row of controls competing with the tile for attention, on a
/// panel whose whole job is to be read at a glance; one chip says what the size
/// *is*, which is the part worth showing all the time. It opens on hover and
/// on focus — hover alone would put a control on the panel that a keyboard
/// cannot reach.
struct EditChrome: ViewModifier {
    let active: Bool
    let widget: String
    let size: PanelWidgetSize
    let sizes: [PanelWidgetSize]
    /// This tile is the one being carried, so it is a slot: no content, and no
    /// controls hanging off a corner that has nothing behind it.
    let lifted: Bool
    /// The slot's grey well — on its own flag, not on `lifted`, because it
    /// outlives the drag and fades after the exact handover.
    let wellVisible: Bool
    /// The mode is arrangement, not use: a clear layer over the tile's own
    /// controls, so a drag can start anywhere on it — a toggle that still
    /// worked would claim the mouse-down and make half of every tile
    /// ungrabbable. The chrome sits above the shield and stays pressable.
    let shielded: Bool

    /// Non-nil for a widget whose corner control chooses something other than a
    /// size — the drawer, which chooses its rows.
    let choose: (() -> Void)?
    let choosing: Bool
    let resize: (PanelWidgetSize) -> Void
    let remove: () -> Void
    let move: (Int) -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    private var open: Bool { hovering || focused }

    /// Named once so the glyph and the swap cannot disagree about which symbol
    /// is on screen — the pair shares nothing, so this is the one of the five
    /// swaps that always takes Magic Replace's fallback.
    private var chooseSymbol: String { choosing ? "checkmark" : "pencil" }

    func body(content: Content) -> some View {
        // **One branch, whatever the mode.** This used to be `if !active {
        // content } else { content.decorated }`, and the two branches are two
        // identities to SwiftUI — entering the edit mode tore every tile down
        // and rebuilt it, so there was nothing to interpolate and the whole
        // grid snapped. That was the judder that survived four animation
        // fixes: it was never the animation, it was the identity.
        content
            // The slot of a tile that is being carried: the content steps
            // aside, a quiet well marks the place, and the overlay above the
            // grid is the one full-weight copy under the pointer.
            .opacity(lifted ? 0 : 1)
            .background {
                // Opacity, not insertion: an `if` is a structural change, and a
                // transition's animation is whatever transaction happens to be
                // running — the pickup's quarter-second spring. A plain opacity
                // is governed by its scoped animation, always — including at
                // the drop, where the content above it swaps inside a
                // transaction that has animations off.
                RoundedRectangle(cornerRadius: HelmRadius.frame, style: .continuous)
                    .fill(HelmSurface.wellFill)
                    .opacity(wellVisible ? 1 : 0)
                    .animation(HelmMotion.wellFade, value: wellVisible)
            }
            // Slow on purpose — slower than the hand. Both durations and the
            // reasons for them live on `HelmMotion.slotFade` / `.wellFade`,
            // which is also where they learned to stop under Reduce Motion.
            .animation(HelmMotion.slotFade, value: lifted)
            .overlay {
                if shielded {
                    Color.clear.contentShape(RoundedRectangle(cornerRadius: HelmRadius.frame, style: .continuous))
                }
            }
            .overlay(alignment: .topLeading) {
                if active, !lifted {
                    Button {
                        withAnimation(HelmMotion.disclosure) { remove() }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(HelmSignal.danger))
                            .shadow(radius: 1, y: 0.5)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -4, y: -4)
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
                                .foregroundStyle(choosing ? Color.white : HelmText.quiet)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Capsule().fill(choosing ? AnyShapeStyle(Color.accentColor)
                                                           : AnyShapeStyle(.regularMaterial)))
                                .overlay(Capsule().strokeBorder(HelmSurface.hairline))
                        }
                        .buttonStyle(.plain)
                        .help(AppStr.chooseUtilities)
                        .accessibilityLabel(AppStr.chooseUtilities)
                    } else {
                        sizeControl
                    }
                }
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
            // The room the corner controls overhang by, exactly: the grid
            // lives in a `ScrollView`, which clips at its own bounds. Animated
            // by the mode's own transaction, since it is part of what the mode
            // changes.
            .padding(active ? 4 : 0)
            // Movable by arrow keys, so the arrangement is not the one part of
            // the panel a keyboard cannot reach. No system ring: it is drawn
            // round the frame and arrived as a hard rectangle over glass.
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
        HStack(spacing: 2) {
            ForEach(open ? sizes : [size], id: \.self) { option in
                Button {
                    // Shut on the way out, and say so *before* the resize.
                    //
                    // The tile changes shape under the pointer, so the control
                    // slides out from under it and `onHover(false)` never
                    // arrives — the pill stayed open, with the chip it had just
                    // chosen lit blue, until something else moved. Clicking also
                    // leaves the button focused, and focus is the other half of
                    // «open».
                    hovering = false
                    focused = false
                    resize(option)
                } label: {
                    // The accent marks *which of the three*, so it appears
                    // only when there are three. Closed, the chip is one label
                    // saying what the size is, and a blue pill on every tile
                    // would be the loudest thing in a panel meant to be read
                    // at a glance.
                    Text(option.label)
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(open && option == size ? Color.white
                                         : HelmText.quiet)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        // A capsule inside a capsule. The container is one, and
                        // a 4 pt rounded rectangle inside it is concentric with
                        // nothing — the corner of the chip cut across the curve
                        // of the pill it sat in. A capsule's radius is half its
                        // own height, so the two are concentric whatever the
                        // type size does to them.
                        .background(Capsule()
                            .fill(open && option == size ? Color.accentColor : .clear))
                }
                .buttonStyle(.plain)
                .help(option.label)
            }
        }
        .padding(2)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(HelmSurface.hairline))
        .focusable()
        .focused($focused)
        // The system ring is drawn round the view's *frame*, and this view is a
        // capsule inside one — so it came out as a rounded rectangle floating
        // around a pill, at a different radius and a different size.
        //
        // Turned off rather than reshaped, because this control already shows
        // its focus by doing something better than a ring: it opens. Three
        // chips where there was one is a clearer «you are here» than a line
        // round the outside, and it is the same signal a pointer gets.
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
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HelmText.quiet)
                    Text(AppStr.utilities).font(.subheadline.weight(.medium))
                    Spacer()
                    // The panel keeps its own scale — 9 · 10 · 11 · 12, spelled
                    // out beside this line — and does not answer to the settings
                    // window's four tokens (ARCHITECTURE.md § Design language).
                    Text("\(modules.count)").font(.caption).foregroundStyle(HelmText.faint)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HelmText.faint)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The count is on screen and was being thrown away: a bare
            // `.accessibilityLabel` *replaces* the label SwiftUI synthesizes
            // from the row, so "Utilities 3 ›" was read as "Utilities". The
            // count goes back as the value, where a number belongs, and the
            // open/closed state with it — a disclosure that will not say
            // whether it is open answers its own button press with silence.
            .accessibilityLabel(AppStr.utilities)
            .accessibilityValue("\(Count(modules.count)), \(HelmA11y.expanded(open))")

            // Measured height rather than `if expanded`: with the rows removed
            // from the hierarchy the card's background collapsed instantly
            // while the disappearing rows kept drawing over whatever sat
            // below. `helmAccordion` is that shape, and why each half of it is
            // there is written on it.
            VStack(spacing: 2) {
                ForEach(modules, id: \.descriptor.idRaw) { live in
                    HStack(spacing: 6) {
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
                            // The tick is the whole face of this control, so
                            // read aloud it was "button" — which module it
                            // admits to the panel is the name, and the tick
                            // itself is the selection, said in the system's
                            // own word rather than through a new key.
                            .accessibilityLabel(live.descriptor.moduleMetadata.shortName)
                            .accessibilityAddTraits(isOn(live.descriptor.idRaw) ? .isSelected : [])
                        }
                    }
                }
            }
            .padding(.top, 8)
            // **The one site where the measurement half is load-bearing.**
            // Everywhere else the block's content is one fixed shape and the
            // only thing that moves is the gate; here the pencil swaps three
            // rows for nine, so the height changes *while the block is open*
            // and has to be seen changing. Measured: 102 → 298 pt in a single
            // frame before the write carried a transaction.
            .helmAccordion(open: open, height: $rowsHeight)
        }
        .helmPanelCard()
    }

    private func utilityRow(_ live: ModuleHost.Live) -> some View {
        let meta = live.descriptor.moduleMetadata
        return Button {
            NotificationCenter.default.post(name: .helmOpenSettings, object: live.descriptor.idRaw)
        } label: {
            HStack(spacing: 8) {
                HelmIconPlate(symbol: meta.sfSymbol,
                              tint: live.descriptor.moduleTint.colour, size: 20)
                // The short name, as the sidebar asks for: this column is
                // fixed and «Объекты входа и расширения» is cut mid-word in it.
                // `.callout` is 12, which is off the settings scale and *on*
                // the panel's own — the sizes around it in this file are 9,
                // 10, 11 and 12. The panel is a transient surface with its
                // own rules (ARCHITECTURE.md § Design language); this is the
                // one style the tree-wide sweep left where it was.
                Text(meta.shortName).font(.callout).lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(HelmText.faint)
                    // Decoration: the row is a button and the arrow only
                    // repeats «opens elsewhere» — read aloud it was a second
                    // anonymous image after every module's name.
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
    // No module count. The widget is 320 pt with a button on the same line, so
    // a second fact there is a paragraph wrapped around a control at the top of
    // the first thing anybody opens when something is wrong. The settings page
    // has the room and says both.

    /// **The banner is the plate.** It used to sit inside `HelmWidgetBody`, which
    /// is a panel card — padding and a fill — and `HelmBanner` draws a filled field
    /// of its own, so the panel showed a card inside a card: a plate with 12 pt of
    /// another plate visible around it, and a height a full widget's rather than a
    /// line's. A widget body is for a widget, which is a figure with a label under
    /// it; this is one sentence and one button, so it takes the row's whole width
    /// like any 2×1 and only the height it needs.
    var body: some View {
        // `HelmBanner`, not a fourth hand-rolled row. This was the shape the
        // banner's own documentation claimed the panel already drew — a mark,
        // some quiet text and a button, spelled out here at 11 pt with no
        // field behind it — while the hero and `HelmPermissionNote` drew the
        // v3 field. One statement, two appearances, decided by which window
        // you happened to open.
        HelmBanner(AppStr.permissionsWithheld(count: withheld.count),
                   symbol: "exclamationmark.circle.fill", compact: true) {
                // One withheld grant has one place to go, so go there. Several
                // do not, and a button that picks one of them silently is a
                // button that lies about what it opened.
                if withheld.count == 1, let only = withheld.first {
                    Button(AppStr.grant) { only.openSettings() }
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
/// It keeps its place: dropping it would take the arrangement apart and leave
/// nobody able to say where the block went, and switching a module off is not
/// a request to rearrange the panel. The plate is drawn inactive, and the one
/// button is the way back.
struct DisabledModuleWidget: View {
    let descriptor: any ModuleDescriptor

    var body: some View {
        HelmWidgetBody {
            HStack(spacing: 8) {
                HelmIconPlate(symbol: descriptor.moduleMetadata.sfSymbol,
                              tint: descriptor.moduleTint.colour, size: 18, active: false)
                Text(descriptor.moduleMetadata.shortName)
                    .font(HelmText.rowTitle.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            Text(AppStr.moduleIsOff)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
            Button(AppStr.turnOn) {
                ModuleHost.shared.setEnabled(descriptor, true)
                NotificationCenter.default.post(name: .helmModuleOrderChanged, object: nil)
            }
            .controlSize(.small)
        }
    }
}
