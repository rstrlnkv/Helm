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
}
public extension ModuleDescriptor {
    /// True when the page draws across the whole pane instead of inside the
    /// 744 pt form column, so its header knows not to centre itself.
    var pageBleeds: Bool { false }
    func statusAppearance(_ vm: ModuleViewModel) -> StatusAppearance { .inactive }
    func statusChanges(_ vm: ModuleViewModel) -> AnyPublisher<Void, Never>? { nil }
}
