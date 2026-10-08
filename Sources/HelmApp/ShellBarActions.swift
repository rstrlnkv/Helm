import AppKit
import HelmUI
import SwiftUI

/// **The page bar's actions zone: one capsule for every action the page declares, hosted in one view.**
///
/// The zone keeps one `HelmToolbarActionsModel` for the bar's life and feeds it on every `show`, so a
/// press, a hidden action coming back and the window's activity all reach the same model. The capsule's
/// width is its reserve, `HelmToolbarActionsCapsule.reserveWidth(of:)`: every *declared* action, shown or
/// not, so a still action stays still when its neighbour appears. The width changes only through `show`,
/// which is why `measuresMoved` is stored and never called.
///
/// **A press runs only while the page is live.** The model's `press` and `pressItem` find the action by
/// id in the page's actions, and only while `show` last said the page is live; a frozen page arrives as
/// the controller's stripped copy (`ShellPageBar.strippedOfClosures`), so the zone holds none of the live
/// page's closures after it.
///
/// **A fresh hosting view is built, over the same model,** when there is none; when the bar's look
/// changed; when another page's actions arrive (`!animated` and the declared ids differ), so the capsule
/// does not morph across pages; and, under Liquid Glass, when the window's activity changed, because
/// whether the capsule's glass follows the window by itself is unresolved in `SettingsToolbar`
/// (`HelmToolbarActionsCapsule`'s header), so the glass look is rebuilt as that bar rebuilds its host.
/// Under `.flat` a change of activity moves the model only. **Not seen on a screen:** this zone in a window.
@MainActor
final class ShellBarActions: ShellBarZone {
    /// The capsule's host; nil while the page declares no action.
    private(set) var view: NSView?
    var measuresMoved: (() -> Void)?

    let model = HelmToolbarActionsModel()

    private let flatInactiveInk: HelmToolbarActionsCapsule.InactiveInk
    /// The page's actions: the live closures while the page is live, the stripped copy after a freeze.
    private var actions: [HelmToolbarAction] = []
    private var isLive = false
    private var width: CGFloat = 0
    private var built: (ids: [String], appearance: HelmBarAppearance, appearsActive: Bool)?

    /// How many switchers `segmentedReserveWidth` has mounted to measure, for a test to read.
    private(set) static var reserveMeasurements = 0
    private struct ReserveKey: Hashable {
        let symbols: [String]
        let appearance: HelmBarAppearance
    }
    /// Every reserve measured, by the options' glyphs in order and by look: a switcher is drawn from its
    /// glyphs alone (`entryContent` fixes the style to `.icons`), and a page that republishes on every
    /// keystroke must not mount a switcher each time. Not bounded: a key is a `.segmented` declaration's
    /// glyphs, and the declarations `command grep -rn 'options: \[$' Sources/Modules` lists spell them as
    /// literals. A page that built its options from data would grow this table with that data, and would
    /// need a ceiling.
    private static var reserveCache: [ReserveKey: CGFloat] = [:]
    /// What a one-option entry gets on top of what a switcher measures alone. The figure, 3 pt, is
    /// `SettingsToolbar`'s, from its measurement of a one-option entry in its capsule, attached in a toolbar;
    /// here it is added, not derived: `TheBarsActionsKeepTheirReserveTests` holds a one-option switcher drawn
    /// in this zone's host, in no window, within the reserve under both looks, and does not ask what the
    /// reserve would be without it.
    private static let oneOptionCapsuleMargin: CGFloat = 3

    init(titlebarIsTransparent: Bool) {
        flatInactiveInk = .init(
            dark: helmNameZoneInactiveOpacity(dark: true, titlebarIsTransparent: titlebarIsTransparent),
            light: helmNameZoneInactiveOpacity(dark: false, titlebarIsTransparent: titlebarIsTransparent))
        model.press = { [weak self] id in
            guard let self, isLive, let action = actions.first(where: { $0.id == id }) else { return }
            Self.perform(action)
        }
        model.pressItem = { [weak self] actionID, itemID in
            guard let self, isLive, let action = actions.first(where: { $0.id == actionID }) else { return }
            switch action.kind {
            case .menu(let items):
                items.first(where: { $0.id == itemID })?.perform()
            case .segmented(let options, let selection):
                guard options.contains(where: { $0.id == itemID }) else { return }
                selection.wrappedValue = itemID
            case .button, .toggle:
                break
            }
        }
    }

    func show(_ state: ShellBarZoneState) {
        actions = state.content?.actions ?? []
        isLive = state.isLive
        var still = Transaction()
        still.disablesAnimations = true

        guard !actions.isEmpty else {
            withTransaction(still) {
                model.setVisibleIDs([])
                model.setDeclared([])
            }
            view = nil
            built = nil
            width = 0
            return
        }

        let entries = Self.entries(for: actions, appearance: state.appearance)
        let ids = entries.map(\.id)
        let rebuilds: Bool
        if let built, view != nil {
            rebuilds = built.appearance != state.appearance
                || (!state.animated && built.ids != ids)
                || (state.appearance == .liquidGlass && built.appearsActive != state.appearsActive)
        } else {
            rebuilds = true
        }

        model.setAppearsActive(state.appearsActive)
        model.setInteractive(!state.isDimmed)
        withTransaction(still) { model.setDeclared(entries) }
        let visible = actions.filter(\.isVisible).map(\.id)
        if visible != model.visibleIDs {
            if state.animated && state.isLive && !rebuilds {
                withAnimation(HelmMotion.interface) { model.setVisibleIDs(visible) }
            } else {
                withTransaction(still) { model.setVisibleIDs(visible) }
            }
        }

        // Built after the model is written: a host made before it would draw the previous page once.
        if rebuilds {
            let host = NSHostingView.inBar(rootView: Root(model: model, ink: flatInactiveInk, appearance: state.appearance))
            host.setAccessibilityLabel(HelmA11y.moreActions)
            view = host
        }
        built = (ids, state.appearance, state.appearsActive)
        // Arithmetic and not the host's `fittingSize`: `measure` must be right as soon as `show` returns.
        width = HelmToolbarActionsCapsule.reserveWidth(of: entries)
    }

    func measure(into measures: inout ShellPageBarView.Measures) {
        measures.actions = width
    }

    /// The capsule's width does not depend on a verdict.
    func apply(_ verdicts: ShellPageBarView.Verdicts) {}

    // MARK: - What a press runs

    /// Runs a `.button` or a `.toggle`; a `.menu` presses through its items and a `.segmented` through its
    /// options, so for those two nothing runs here.
    private static func perform(_ action: HelmToolbarAction) {
        switch action.kind {
        case .button(let perform): perform()
        case .toggle(_, let perform): perform()
        case .menu, .segmented: break
        }
    }

    // MARK: - The model's entries

    /// The closure-free entries the capsule draws from; no closure of the page reaches the model.
    static func entries(for actions: [HelmToolbarAction],
                        appearance: HelmBarAppearance) -> [HelmToolbarActionsModel.Entry] {
        actions.map { action in
            let kind: HelmToolbarActionsModel.EntryKind
            switch action.kind {
            case .button:
                kind = .button
            case .toggle(let isOn, _):
                kind = .toggle(isOn: isOn)
            case .menu(let items):
                kind = .menu(items.map {
                    HelmToolbarActionsModel.MenuEntry(id: $0.id, title: $0.title, isOn: $0.isOn, isEnabled: $0.isEnabled)
                })
            case .segmented(let options, let selection):
                kind = .segmented(options.map {
                    HelmToolbarActionsModel.SegmentEntry(id: $0.id, title: $0.title, symbol: $0.symbol)
                }, selectedID: selection.wrappedValue,
                   reserveWidth: segmentedReserveWidth(options, appearance: appearance))
            }
            return HelmToolbarActionsModel.Entry(id: action.id, title: action.title, symbol: action.symbol,
                                                 isEnabled: action.isEnabled, isBusy: action.isBusy, kind: kind,
                                                 toggleFace: action.toggleFace)
        }
    }

    /// **A `.segmented` entry's reserve: the width of the switcher the capsule will draw, in the look it
    /// will draw it in, measured once per glyph set and look.** The switcher is mounted alone in a
    /// detached hosting view, non-compact and in `.icons`, and read as `fittingSize.width` after a layout
    /// pass. The first option stands for whichever is picked, no options reserve nothing, a one-option
    /// entry gets `oneOptionCapsuleMargin`, and the result is rounded up to a whole point. A zero reading
    /// is not cached. **Compared with the switcher drawn inside the capsule's host under both looks, in no
    /// window** (`TheBarsActionsKeepTheirReserveTests`): the drawn control is no wider than the reserve. Not
    /// compared in a window or in a bar: `SettingsToolbar`'s measurement is taken attached, in a toolbar, and
    /// this one is not.
    static func segmentedReserveWidth(_ options: [HelmToolbarTab], appearance: HelmBarAppearance) -> CGFloat {
        guard let first = options.first else { return 0 }
        let key = ReserveKey(symbols: options.map(\.symbol), appearance: appearance)
        if let cached = reserveCache[key] { return cached }
        let switcher = HelmToolbarSwitcher(
            HelmA11y.whatToShow, selection: .constant(first.id),
            segments: options.map { HelmSwitcherSegment($0.id, $0.title, symbol: $0.symbol) },
            appearance: appearance)
            .environment(\.helmSwitcherStyle, .icons)
        let host = NSHostingView.inBar(rootView: switcher)
        host.layoutSubtreeIfNeeded()
        reserveMeasurements += 1
        var measured = host.fittingSize.width
        guard measured > 0 else { return 0 }
        if options.count == 1 { measured += oneOptionCapsuleMargin }
        measured = measured.rounded(.up)
        reserveCache[key] = measured
        return measured
    }

    /// The capsule with the look and the flat dimming numbers the zone carries. It has no inset of its
    /// own: the bar's layout owns the right margin (`ShellBarLayout.trailing`).
    private struct Root: View {
        let model: HelmToolbarActionsModel
        let ink: HelmToolbarActionsCapsule.InactiveInk
        let appearance: HelmBarAppearance

        var body: some View {
            HelmToolbarActionsCapsule(model, flatInactiveInk: ink)
                .environment(\.helmBarAppearance, appearance)
        }
    }
}
