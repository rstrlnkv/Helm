import SwiftUI
import Combine
import HelmContract
import HelmRuntime

@MainActor public protocol ModuleDescriptor {
    /// What this module's pages, menu-bar contribution and panel tiles are drawn
    /// from, and what the module itself ends in `stop(_:)`.
    associatedtype Model: AnyObject
    static var id: ModuleID { get }
    /// **Computed on every read, never stored.** `ModuleMetadata` is finished
    /// strings, so a `static let` would keep the language of the first read
    /// until a restart, and the sidebar, page headers, welcome steps and panel
    /// would keep old names after a language switch.
    /// `AModuleNamesItselfInTodaysLanguageTests` fails per module on a stored one.
    static var metadata: ModuleMetadata { get }
    static var category: ModuleCategory { get }
    /// The colour this module is known by.
    ///
    /// Deliberately not defaulted: a default would let a module ship without a
    /// colour of its own and share one silently. The compiler asking is better
    /// than a test noticing.
    static var tint: ModuleTint { get }
    /// The shape this module is known by, beside its colour.
    ///
    /// Deliberately not defaulted, for the reason `tint` is not.
    static var glyph: ShellGlyph { get }
    /// The engine for this module and the model drawn from it, built together
    /// (the host owns the lifecycle). `store` is the module's namespaced store.
    ///
    /// **And nothing else.** It builds objects; it does not start anything and
    /// does not touch the machine: `activate()` is where a module reaches the
    /// system, and `attachMenuBarPresence()` is where it appears in the menu
    /// bar. An engine built against a configured store, as a measurement does,
    /// must not put anything on somebody's Mac.
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
    /// The door another module removes an app through: only the Uninstaller answers, and nil
    /// is "no such door now" (stopped, or not this module), never an empty service.
    func appRemoval(_ model: Model) -> (any AppRemovalService)?
    /// A presence in the menu bar this module owns outright, apart from Helm's
    /// own status item, such as Keyboard's language indicator.
    ///
    /// Called by the host when the module starts running and undone when it
    /// stops, so «this module is live» and «this module is in the menu bar» are
    /// one fact. Both default to nothing.
    func attachMenuBarPresence()
    func detachMenuBarPresence()
    func menuBar(_ model: Model) -> MenuBarContribution?
    func settingsPage(_ model: Model) -> AnyView
    /// Whether this module is doing something right now — for the badge beside
    /// its name in the page header.
    ///
    /// Nil by default: «active» has to mean something the module can say.
    /// `statusAppearance` is not that answer: it reports a claim on the
    /// menu-bar icon, so Disk in the middle of a scan returns `.inactive`, and a
    /// badge drawn from it would say the scan was not running.
    func activity(_ model: Model) -> ModuleActivity?
    /// The permissions this module needs **as it is configured right now**.
    ///
    /// `metadata.permissions` is what a module would use with everything
    /// switched on, right for a table of what it can do and wrong for asking:
    /// Keep Awake declares `.accessibility` for a pointer nudge that ships off,
    /// and asking for it at first launch would offer the widest input grant
    /// macOS has for a switch nobody touched. Defaults to the declared list.
    func currentPermissions() -> [ModulePermission]
    /// Desired host status-icon appearance for the model's current state. Default = inactive (white ring).
    func statusAppearance(_ model: Model) -> StatusAppearance
    /// Fires when what `statusAppearance` or `activity` reads may have changed:
    /// the host redraws the icon, and the page header re-reads the badge.
    ///
    /// A module whose icon or badge follows its own view state keeps that state
    /// out of the host's reach, so the host cannot watch a shared object for it.
    /// Nil means the host has nothing to watch here.
    func statusChanges(_ model: Model) -> AnyPublisher<Void, Never>?
    /// The global shortcuts this module owns. Default: none.
    ///
    /// Static, so the host reads them in one loop over the registry whether or
    /// not the module was ever built — a switched-off module never is; each is
    /// held only while the module is live, and a switched-off module holds no key.
    static var hotkeys: [ModuleHotkey] { get }
    /// A declared shortcut was pressed while the module is live.
    func hotkeyPressed(_ hotkey: ModuleHotkey, _ model: Model)
    /// The widget this module puts in the panel at a given size, or nil if it
    /// has nothing worth saying at that size.
    ///
    /// A size is a different question, not a smaller answer: 1×1 says how
    /// much, 2×1 how much and what to do about it, 2×N why it is that much. A
    /// module returns nil for a size it has no answer for, and the panel clamps
    /// a stored choice to what is offered rather than dropping the widget.
    func panelWidget(_ size: PanelWidgetSize, _ model: Model) -> AnyView?
    /// Which sizes the above answers for. See the default.
    func panelWidgetSizes(_ model: Model) -> Set<PanelWidgetSize>
}
public extension ModuleDescriptor {
    func backgroundScan(_ parts: ModuleParts<Model>) async -> ScanReport? { nil }
    func appRemoval(_ model: Model) -> (any AppRemovalService)? { nil }
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

    /// Every module draws one panel tile the width of the card, which is
    /// `wide`, so the default answers `wide` with that tile and nil for the
    /// rest. A module overrides it when it has the other sizes.
    func panelWidget(_ size: PanelWidgetSize, _ model: Model) -> AnyView? {
        guard size == .wide else { return nil }
        return menuBar(model)?.panelTile
    }

    /// Probed from `panelWidget`, so a module that overrides one gets the
    /// other for free. Override it only where building the view is expensive:
    /// this is asked once per layout pass.
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
/// Two cases and no third: this is not a place for progress or counts. The
/// first is a green badge, the second quiet text, because «not active» is the
/// ordinary state and a badge for it would mean nothing.
public enum ModuleActivity: Equatable, Sendable {
    case active
    case idle
}
