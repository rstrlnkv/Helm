import SwiftUI

// **What a settings page may put in the header row of the card, said once here so
// every module page says it the same way.** The row is drawn by `helmCardHeader`
// (`HelmCardHeader.swift`) from `HelmHeaderContentKey`, a preference: the page and the row
// live in one hosting view, so what a page declares travels up to the row and no object
// in another target has to be reached.
//
// A module's UI target imports `HelmUI` and never `HelmApp` — so this file is where a
// page-facing name has to live.

/// One tab a page declares for the header row's tab strip, said as data
/// rather than as a view, since a module's UI target cannot build
/// the header row's own tabs (`HelmHeaderTabs`) directly.
public struct HelmHeaderTab {
    /// Stable, and the value a segment's selection is compared against — not
    /// an index, which a tab list that ever reorders would silently mis-read.
    public let id: String
    /// Localised already: every string that reaches a person in this app is
    /// looked up once, at the page; `HelmHeaderTabs` draws `title` and speaks it to
    /// VoiceOver as it is given and looks nothing up.
    public let title: String
    /// The SF Symbol the tab draws when the row's tabs are labelled by glyphs (`HeaderTabLabels`): alone, with the
    /// word in the tooltip, or beside the word (`HelmHeaderTabs`). Required, so no page has a tab without one.
    public let symbol: String
    /// **A dot on the tab: this tab has something to say that the page below it does not shout.** False for every
    /// tab that has nothing, so the pages that never say it draw as before. The tabs draw the dot beside the word
    /// (`HelmHeaderTabs`). The page switches it by the same reading its own rows say the thing from, or the dot and the tab say different things.
    public let needsAttention: Bool
    /// What the dot says, localised already, for VoiceOver (the tab's accessibility value); nil is the dot alone.
    public let attentionNote: String?

    public init(id: String, title: String, symbol: String, needsAttention: Bool = false,
                attentionNote: String? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.needsAttention = needsAttention
        self.attentionNote = attentionNote
    }
}

/// One item in a `.menu`-kind `HelmHeaderAction`'s own submenu — a check
/// beside a title, with a press of its own rather than the action's single
/// `perform`: Leftovers' kind filter is the first caller, one checkmark per
/// `StaleKind`.
public struct HelmHeaderMenuItem {
    let id: String
    public let title: String
    let isOn: Bool
    let isEnabled: Bool
    let perform: () -> Void

    public init(id: String, title: String, isOn: Bool, isEnabled: Bool = true,
                perform: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.perform = perform
    }
}

/// **A toggle whose state is its glyph.** The row tints a plain toggle's
/// glyph with the accent when it is on; a toggle given a face is never tinted
/// and draws `offSymbol` when off and its own `symbol` when on — the open eye
/// and the slashed one for Follow — and says what it is doing as its
/// accessibility value, which a glyph swap alone does not say to VoiceOver.
/// Closure-free on purpose, so it stays `Equatable`.
public struct HelmHeaderToggleFace: Equatable, Sendable {
    let offSymbol: String
    let onValue: String
    let offValue: String

    public init(offSymbol: String, onValue: String, offValue: String) {
        self.offSymbol = offSymbol
        self.onValue = onValue
        self.offValue = offValue
    }

    /// The glyph to draw: the action's own symbol when on, `offSymbol` when off.
    func symbol(isOn: Bool, on symbol: String) -> String { isOn ? symbol : offSymbol }

    /// The accessibility value to say, one word pair for the two states.
    func value(isOn: Bool) -> String { isOn ? onValue : offValue }
}

/// One button in the header row's run of actions (`HelmHeaderActions`).
public struct HelmHeaderAction {
    /// **What the action draws as and what pressing it does — one shape, not
    /// three optionals a caller could set inconsistently.** A plain button
    /// runs `perform` on a press; a toggle also carries its own current
    /// state, read back into the glyph's tint; a menu has no single
    /// `perform` at all, only the items inside it, each with its own — so a
    /// menu that is also a toggle, or a toggle with a submenu, cannot be
    /// written down.
    enum Kind {
        case button(() -> Void)
        case toggle(isOn: Bool, () -> Void)
        case menu([HelmHeaderMenuItem])
    }

    let id: String
    /// Said in the tooltip and in the accessibility label — a glyph-only
    /// control has no other name.
    public let title: String
    let symbol: String
    /// **Dimmed while it stays in the row, and inapplicable *there* rather
    /// than inapplicable everywhere.** An action a page shows on only some of
    /// its own tabs is out of the row's visible set on the rest
    /// (`isVisible`), and on the tab where it belongs it is dimmed
    /// until it can act.
    let isEnabled: Bool
    /// **Whether this action belongs on the tab currently showing at all.**
    /// `true` for an action every tab offers (Homebrew's Refresh); `false`
    /// does not draw a button for it — the row still
    /// reserves its width from the *declared* set regardless, which is
    /// what keeps every other button still when this one appears or
    /// disappears (`HelmHeaderActions`).
    let isVisible: Bool
    /// Spinning in the row while `true` — `.helmSteadySpin`, which
    /// already honours Reduce Motion (`HelmMotion.swift`). Only the plain
    /// `.button` initializer below takes this as a parameter: a toggle's own
    /// state is what its glyph already reports, and a menu has no one glyph
    /// whose state a spin would report on either, so both initializers below
    /// leave it `false` and there is no way to write a spinning toggle or
    /// menu down at all outside this target.
    let isBusy: Bool
    let kind: Kind
    /// Set only by the toggle initializer that takes one; nil for every other
    /// action, which draws exactly as it did before there was a face.
    let toggleFace: HelmHeaderToggleFace?
}

extension HelmHeaderAction {
    /// A plain button: a `perform` and nothing else. A toggle and a menu take the initializers below.
    public init(id: String, title: String, symbol: String, isEnabled: Bool = true,
                isVisible: Bool = true, isBusy: Bool = false, perform: @escaping () -> Void) {
        self.init(id: id, title: title, symbol: symbol, isEnabled: isEnabled, isVisible: isVisible,
                  isBusy: isBusy, kind: .button(perform), toggleFace: nil)
    }

    /// A toggle: `isOn` decides the glyph's tint — or, given a `face`, which of
    /// two glyphs is drawn, untinted — and the same `perform` convention as a
    /// plain button: the caller flips its own state, which the next declare
    /// reads back into `isOn`.
    public init(id: String, title: String, symbol: String, isEnabled: Bool = true,
                isVisible: Bool = true, isOn: Bool, face: HelmHeaderToggleFace? = nil,
                perform: @escaping () -> Void) {
        self.init(id: id, title: title, symbol: symbol, isEnabled: isEnabled, isVisible: isVisible,
                  isBusy: false, kind: .toggle(isOn: isOn, perform), toggleFace: face)
    }

    /// A menu of checkmarked items — no `perform` of the action's own; each
    /// item carries its own.
    public init(id: String, title: String, symbol: String, isEnabled: Bool = true,
                isVisible: Bool = true, menu: [HelmHeaderMenuItem]) {
        self.init(id: id, title: title, symbol: symbol, isEnabled: isEnabled, isVisible: isVisible,
                  isBusy: false, kind: .menu(menu), toggleFace: nil)
    }
}

/// The page's search: a binding kept live on every keystroke, and a submit
/// action that fires on Return and on Return only — `sendsWholeSearchString`
/// is what makes that true on the AppKit side, so nothing here has to filter
/// keystrokes itself.
public struct HelmHeaderQuery {
    let prompt: String
    var text: Binding<String>
    let onSubmit: (() -> Void)?

    public init(prompt: String, text: Binding<String>, onSubmit: (() -> Void)? = nil) {
        self.prompt = prompt
        self.text = text
        self.onSubmit = onSubmit
    }
}

/// **The whole of what a page asks the window's header row to show**, beyond the
/// name every page gets for nothing. Any of the three may be empty or nil — a
/// page with none of them gets a row with the name only, not an error; a page
/// that has nothing to declare simply never calls `helmHeaderContent`.
public struct HelmHeaderContent {
    public var tabs: [HelmHeaderTab]
    /// nil when `tabs` is empty; set when it is not. Two facts kept apart
    /// rather than folded into one, for the reason a lone `Binding` never
    /// says whether there is anything to select from.
    public var selectedTab: Binding<String>?
    /// **Dims the whole tab strip** — Uninstaller's during its review step, so
    /// far the one caller — rather than any one tab: per-tab disabling was
    /// never asked for, so there is nothing here to disable a tab by.
    var tabsEnabled: Bool
    public var actions: [HelmHeaderAction]
    var search: HelmHeaderQuery?

    public init(tabs: [HelmHeaderTab] = [], selectedTab: Binding<String>? = nil, tabsEnabled: Bool = true,
                actions: [HelmHeaderAction] = [], search: HelmHeaderQuery? = nil) {
        self.tabs = tabs
        self.selectedTab = selectedTab
        self.tabsEnabled = tabsEnabled
        self.actions = actions
        self.search = search
    }
}

/// **What the page on screen declared for the header row, as facts**: the same declaration the row draws, for what
/// outside the row must agree with it (the window's right-click menu: Tab labels only with tabs, Always Collapse
/// Search only with a search).
public struct HelmPageHeaderFacts: Equatable, Sendable {
    public let hasTabs: Bool
    public let hasSearch: Bool
}

/// The page's `HelmPageHeaderFacts`, nil where it declared nothing; the last declaration in tree order wins.
public struct HelmPageHeaderFactsKey: PreferenceKey {
    public static let defaultValue: HelmPageHeaderFacts? = nil

    public static func reduce(value: inout HelmPageHeaderFacts?, nextValue: () -> HelmPageHeaderFacts?) {
        value = nextValue() ?? value
    }
}

/// **What the page on screen declared for the header row**, nil where it declared nothing.
///
/// The last declaration in tree order wins, as the title's does (`HelmPageTitleKey`). The default is computed:
/// the value holds closures and is not `Sendable`, which a stored static would have to be.
struct HelmHeaderContentKey: PreferenceKey {
    static var defaultValue: HelmHeaderContent? { nil }

    static func reduce(value: inout HelmHeaderContent?, nextValue: () -> HelmHeaderContent?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// **The one way a page's header content reaches the window.**
    ///
    /// **Now a preference, read by the header row in the card** (`helmCardHeader`, `HelmCardHeader.swift`):
    /// the page sits in the same hosting view as the row, so what it declares travels up the tree and the row
    /// reads it with `overlayPreferenceValue`, which asks nothing of the value — a `perform` closure is never
    /// `Equatable`.
    public func helmHeaderContent(_ content: HelmHeaderContent?) -> some View {
        preference(key: HelmHeaderContentKey.self, value: content)
            .preference(key: HelmPageHeaderFactsKey.self,
                        value: content.map { HelmPageHeaderFacts(hasTabs: !$0.tabs.isEmpty, hasSearch: $0.search != nil) })
    }
}

