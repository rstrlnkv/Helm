import SwiftUI
import Combine
import HelmContract
import HelmRuntime

@MainActor public protocol ModuleDescriptor {
    static var id: ModuleID { get }
    static var metadata: ModuleMetadata { get }
    static var category: ModuleCategory { get }
    /// The colour this module is known by.
    ///
    /// Deliberately not defaulted. A default would let a module ship without a
    /// colour of its own and inherit one silently — which is the defect this
    /// replaces, where `ModuleCategory.tint` gave four «files» modules one
    /// blue. The compiler asking is better than a test noticing.
    static var tint: ModuleTint { get }
    /// Build the engine for this module (host owns lifecycle). `store` is the module's namespaced store.
    func makeEngine(store: NamespacedStore) -> any ModuleEngine
    func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution?
    func settingsPage(_ vm: ModuleViewModel) -> AnyView
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
    func activity(_ vm: ModuleViewModel) -> ModuleActivity?
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
    func currentPermissions(_ vm: ModuleViewModel?) -> [ModulePermission]
    /// Desired host status-icon appearance for the current vm state. Default = inactive (white ring).
    func statusAppearance(_ vm: ModuleViewModel) -> StatusAppearance
    /// Fires when the value `statusAppearance` reads has changed.
    ///
    /// A module that tints the menu-bar icon keeps its own view state, so the
    /// host cannot watch a shared object for it. Only Keep Awake answers this;
    /// the default is nil, which means "this module never changes the icon".
    func statusChanges(_ vm: ModuleViewModel) -> AnyPublisher<Void, Never>?
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
    func panelWidget(_ size: PanelWidgetSize, _ vm: ModuleViewModel) -> AnyView?
    /// Which sizes the above answers for. See the default.
    func panelWidgetSizes(_ vm: ModuleViewModel) -> Set<PanelWidgetSize>
}
public extension ModuleDescriptor {
    /// True when the page draws across the whole pane instead of inside the
    /// 744 pt form column, so its header knows not to centre itself.
    var pageBleeds: Bool { false }
    func statusAppearance(_ vm: ModuleViewModel) -> StatusAppearance { .inactive }
    func activity(_ vm: ModuleViewModel) -> ModuleActivity? { nil }
    func currentPermissions(_ vm: ModuleViewModel?) -> [ModulePermission] {
        Self.metadata.permissions
    }
    func statusChanges(_ vm: ModuleViewModel) -> AnyPublisher<Void, Never>? { nil }

    /// Every module already draws one panel tile the width of the card, and
    /// that is exactly `wide`. So the default answers `wide` with the tile it
    /// already has and nil for the rest — the panel becomes a grid of
    /// one-size widgets on the day this lands, identical to what it was, and
    /// each module grows its other two sizes when somebody writes them. No
    /// flag day, and no nine-module commit before anything can be seen.
    func panelWidget(_ size: PanelWidgetSize, _ vm: ModuleViewModel) -> AnyView? {
        guard size == .wide else { return nil }
        return menuBar(vm)?.panelTile
    }

    /// Probed from `panelWidget`, so a module that overrides one gets the
    /// other for free. Worth overriding only where building the view is
    /// expensive enough to matter — answering this is asked once per layout
    /// pass and building a widget is not.
    func panelWidgetSizes(_ vm: ModuleViewModel) -> Set<PanelWidgetSize> {
        Set(PanelWidgetSize.allCases.filter { panelWidget($0, vm) != nil })
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
