import SwiftUI
import HelmContract
import HelmRuntime

@MainActor public protocol ModuleDescriptor {
    static var id: ModuleID { get }
    static var metadata: ModuleMetadata { get }
    static var isolation: ModuleIsolation { get }
    static var category: ModuleCategory { get }
    /// Build the engine for this module (host owns lifecycle). `store` is the module's namespaced store.
    func makeEngine(store: NamespacedStore) -> any ModuleEngine
    func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution?
    func settingsPage(_ vm: ModuleViewModel) -> AnyView
    /// Desired host status-icon appearance for the current vm state. Default = inactive (white ring).
    func statusAppearance(_ vm: ModuleViewModel) -> StatusAppearance
}
public extension ModuleDescriptor {
    func statusAppearance(_ vm: ModuleViewModel) -> StatusAppearance { .inactive }
}
