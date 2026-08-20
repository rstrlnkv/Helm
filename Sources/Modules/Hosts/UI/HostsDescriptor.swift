import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Hosts_Engine

@MainActor public final class HostsDescriptor: ModuleDescriptor {
    public static let id = ModuleID(HostsEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: HostsStr.moduleName, shortName: HostsStr.moduleNameShort,
        summary: HostsStr.summary,
        sfSymbol: "network", permissions: []) }
    public static let category: ModuleCategory = .utilities
    public static let tint: ModuleTint = .hosts

    /// **The page draws across the whole pane, so its header must not centre
    /// itself.** Two tab strips, a table and an unsaved bar, each at
    /// `HelmLayout.formInset` — not a grouped `Form` anywhere on it. Without
    /// this the header sat on the 744 pt column while the controls sat at the
    /// pane's leading edge: measured at an 845 pt pane the plate was at x 70
    /// with the first control at x 20, and at 1400 the gap was 328 pt.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        HostsEngine()
    }

    /// **A utility, so the panel lists it and does not draw it.**
    ///
    /// It had a tile of three counts and no control, and a tile with nothing to
    /// press is exactly what `MenuBarContribution.isUtility` describes: the
    /// panel is for what can be acted on from the menu bar, and everything this
    /// module can do — editing the hosts file, fixing a key's mode, reading a
    /// fingerprint — is a page. Counting on the panel was the module asking for
    /// a widget's worth of somebody's glass to say «go and open Settings».
    ///
    /// The reason the tile carried no control in the first place stands and is
    /// why no tile is coming back: a hosts toggle in the panel is a macOS
    /// password dialog raised from the menu bar, and a password dialog needs a
    /// gesture that asked for it.
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(HostsSettingsPage(vm: vm))
    }
}
