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
