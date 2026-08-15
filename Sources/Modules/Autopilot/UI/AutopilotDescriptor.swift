import HelmContract
import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

@MainActor public final class AutopilotDescriptor: ModuleDescriptor {
    public static let id = ModuleID("autopilot")
    /// **The one module that has something to hand over on a first launch.**
    /// Every other one either works the moment it is switched on or waits for a
    /// gesture; this one does nothing at all until somebody writes a rule, and a
    /// tour that left them at «Autopilot: folders that keep themselves in order»
    /// has described a feature and delivered none of it. The offer is the way to
    /// the five rules they can have without writing one.
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: ApStr.moduleName, summary: ApStr.summary,
        sfSymbol: "location.north.circle", permissions: [.fullDisk],
        welcomeOffer: ApStr.welcomeOffer) }
    public static let category: ModuleCategory = .files
    public static let tint: ModuleTint = .autopilot
    /// Folders and their rules span the pane; the header must not centre itself
    /// on the 744 pt form column.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        AutopilotEngine(store: store)
    }

    /// Not a utility any more: how many folders it watches and what it did
    /// today are figures worth a glance, which is the whole test for whether a
    /// module belongs in the panel rather than behind a disclosure in it.
    /// A row in the utilities list, not a tile.
    ///
    /// It had a widget for a while — the count of watched folders, the words
    /// put right today — and both are numbers without a question behind them:
    /// nobody opens a menu bar to find out how many folders are watched. A tile
    /// has to earn its 90 pt, and this one was earning it by existing.
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(AutopilotSettingsPage(vm: vm))
    }
}
