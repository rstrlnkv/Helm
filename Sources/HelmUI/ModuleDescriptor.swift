import SwiftUI
import Combine
import HelmContract
import HelmRuntime

@MainActor public protocol ModuleDescriptor {
    /// What this module's pages, menu-bar contribution and panel tiles are drawn
    /// from, and what the module itself ends in `stop(_:)`.
    associatedtype Model: AnyObject
    static var id: ModuleID { get }
    /// **Computed on every read, never stored.** `ModuleMetadata` is a struct of
    /// finished strings, so a `static let` calls `L()` once — the first time
    /// anything in the process touches the descriptor — and keeps that language
    /// until the app is restarted. All nine were declared that way, and the
    /// sidebar, the page headers, the welcome steps and the panel all draw the
    /// module's name from here: switching language in Settings redrew the pages
    /// under names that did not change, which is the one thing the in-app picker
    /// exists to avoid. `AModuleNamesItselfInTodaysLanguageTests` fails per
    /// module on a stored one.
    static var metadata: ModuleMetadata { get }
    static var category: ModuleCategory { get }
    /// The colour this module is known by.
    ///
    /// Deliberately not defaulted. A default would let a module ship without a
    /// colour of its own and inherit one silently — which is the defect this
    /// replaces, where a colour per category gave four «files» modules one
    /// blue. The compiler asking is better than a test noticing.
    static var tint: ModuleTint { get }
    /// The shape this module is known by, beside its colour.
    ///
    /// Deliberately not defaulted, for the reason `tint` is not: a default would
    /// let a module ship without a shape of its own and share another's, and the
    /// compiler asking is better than a test noticing.
    static var glyph: ShellGlyph { get }
    /// The engine for this module and the model drawn from it, built together
    /// (the host owns the lifecycle). `store` is the module's namespaced store.
    ///
    /// **And nothing else.** It builds objects; it does not start anything and
    /// does not touch the machine — `activate()` is where a module reaches the
    /// system, and `attachMenuBarPresence()` is where it appears in the menu
    /// bar. Keyboard's used to do the third of those inside the first, so a
    /// measurement that built an engine against a configured store put a status
    /// item on somebody's Mac.
    func makeModule(store: NamespacedStore) -> ModuleParts<Model>
    /// The model's own deactivation: the host calls it on the person's switch
    /// and on quit, before the engine's `deactivate()`, and never on a refused
    /// stand-in switch or on «Reset all settings» handing the system back. The
    /// model is dropped with the module's `Live` right after.
    func stop(_ model: Model)
    /// One scan, as the host's scheduler asks for it: nil is no answer, not an
    /// empty report. Asked only of the modules `ScanRunner.scannableModules`
    /// lists; each of them overrides this.
    func backgroundScan(_ parts: ModuleParts<Model>) async -> ScanReport?
    /// A presence in the menu bar this module owns outright, apart from Helm's
    /// own status item — Keyboard's language indicator is the only one today.
    ///
    /// Called by the host when the module starts running and undone when it
    /// stops, so «this module is live» and «this module is in the menu bar» are
    /// one fact. Both default to nothing: a module with no presence of its own
    /// says so by not overriding them.
    func attachMenuBarPresence()
    func detachMenuBarPresence()
    func menuBar(_ model: Model) -> MenuBarContribution?
    func settingsPage(_ model: Model) -> AnyView
    /// Whether this module is doing something right now — for the badge beside
    /// its name in the page header.
    ///
    /// Nil by default, and nil is the honest answer for most modules: «active»
    /// has to mean something the module can actually say. `statusAppearance`
    /// is not that answer, however tempting — it reports a *claim on the
    /// menu-bar icon*, so Disk in the middle of a scan returns `.inactive` and
    /// a badge drawn from it would tell the person their scan was not running.
    /// A module answers this when it has a running/not-running of its own, and
    /// gets no badge until it does.
    func activity(_ model: Model) -> ModuleActivity?
    /// The permissions this module needs **as it is configured right now**.
    ///
    /// `metadata.permissions` answers a different question — what a module
    /// would use if everything in it were switched on — and that is the right
    /// answer for a settings table listing what a module is capable of. It is
    /// the wrong one for asking. Keep Awake declares `.accessibility` because
    /// its pointer nudge posts synthetic events; the nudge ships off, so a
    /// first launch put a modal in front of somebody offering the widest input
    /// grant macOS has, for a switch they had never touched. And because this
    /// bundle is ad-hoc signed, every update drops the grant and asks again.
    ///
    /// Defaults to the declared list, so a module that has nothing conditional
    /// says nothing new.
    func currentPermissions() -> [ModulePermission]
    /// Desired host status-icon appearance for the model's current state. Default = inactive (white ring).
    func statusAppearance(_ model: Model) -> StatusAppearance
    /// Fires when the value `statusAppearance` reads has changed.
    ///
    /// A module that tints the menu-bar icon keeps its own view state, so the
    /// host cannot watch a shared object for it. Only Keep Awake answers this;
    /// the default is nil, which means "this module never changes the icon".
    func statusChanges(_ model: Model) -> AnyPublisher<Void, Never>?
    /// The global shortcuts this module owns. Default: none.
    ///
    /// Static, so the host reads them in one loop over the registry whether or
    /// not the module was ever built — a switched-off module never is; each is
    /// held only while the module is live, and a switched-off module holds no key.
    static var hotkeys: [ModuleHotkey] { get }
    /// A declared shortcut was pressed while the module is live.
    func hotkeyPressed(_ hotkey: ModuleHotkey, _ model: Model)
    /// See the default implementation below.
    var pageBleeds: Bool { get }
    /// The widget this module puts in the panel at a given size, or nil if it
    /// has nothing worth saying at that size.
    ///
    /// A size is a different question, not a smaller answer: 1×1 says how
    /// much, 2×1 says how much and what to do about it, 2×N says why it is
    /// that much. A module that only knows the middle answer says so by
    /// returning nil for the other two, and the panel clamps somebody's stored
    /// choice to what is actually offered rather than dropping the widget.
    func panelWidget(_ size: PanelWidgetSize, _ model: Model) -> AnyView?
    /// Which sizes the above answers for. See the default.
    func panelWidgetSizes(_ model: Model) -> Set<PanelWidgetSize>
}
public extension ModuleDescriptor {
    func stop(_ model: Model) {}
    func backgroundScan(_ parts: ModuleParts<Model>) async -> ScanReport? { nil }
    /// True when the page draws across the whole pane instead of inside the
    /// 744 pt form column, so its header knows not to centre itself.
    var pageBleeds: Bool { false }
    func statusAppearance(_ model: Model) -> StatusAppearance { .inactive }
    func attachMenuBarPresence() {}
    func detachMenuBarPresence() {}
    func activity(_ model: Model) -> ModuleActivity? { nil }
    func currentPermissions() -> [ModulePermission] {
        Self.metadata.permissions
    }
    func statusChanges(_ model: Model) -> AnyPublisher<Void, Never>? { nil }
    static var hotkeys: [ModuleHotkey] { [] }
    func hotkeyPressed(_ hotkey: ModuleHotkey, _ model: Model) {}

    /// Every module already draws one panel tile the width of the card, and
    /// that is exactly `wide`. So the default answers `wide` with the tile it
    /// already has and nil for the rest — the panel becomes a grid of
    /// one-size widgets on the day this lands, identical to what it was, and
    /// each module grows its other two sizes when somebody writes them. No
    /// flag day, and no nine-module commit before anything can be seen.
    func panelWidget(_ size: PanelWidgetSize, _ model: Model) -> AnyView? {
        guard size == .wide else { return nil }
        return menuBar(model)?.panelTile
    }

    /// Probed from `panelWidget`, so a module that overrides one gets the
    /// other for free. Worth overriding only where building the view is
    /// expensive enough to matter — answering this is asked once per layout
    /// pass and building a widget is not.
    func panelWidgetSizes(_ model: Model) -> Set<PanelWidgetSize> {
        Set(PanelWidgetSize.allCases.filter { panelWidget($0, model) != nil })
    }
}

/// A global shortcut a module declares. The host registers every one at launch;
/// it is held while the module is live and nothing while it is off.
public struct ModuleHotkey: Equatable, Sendable {
    /// The name `HotkeyManager` files the binding under and `HotkeyStatus`
    /// reports; not stored anywhere.
    public let slot: String
    /// `<prefix>KeyCode`, `<prefix>Modifiers`, `<prefix>Label` in the module's
    /// own store. Deployed data: it never moves, so it has no default here.
    public let prefix: String
    /// The combination used only while the store holds no key at all.
    public let fallback: HotkeyFallback?

    public init(slot: String, prefix: String, fallback: HotkeyFallback? = nil) {
        self.slot = slot
        self.prefix = prefix
        self.fallback = fallback
    }
}

/// What `makeModule` builds: the engine and the model drawn from it.
public struct ModuleParts<Model: AnyObject> {
    public let engine: any ModuleEngine
    public let model: Model
    public init(engine: any ModuleEngine, model: Model) {
        self.engine = engine
        self.model = model
    }
}

/// What a module says about itself in its page header.
///
/// Two cases and no third: this is not a place for progress or counts. v3
/// draws the first as a green badge and the second as quiet text, because
/// «not active» is the ordinary state and a badge for it would be a mark on
/// every page that means nothing.
public enum ModuleActivity: Equatable, Sendable {
    case active
    case idle
}
