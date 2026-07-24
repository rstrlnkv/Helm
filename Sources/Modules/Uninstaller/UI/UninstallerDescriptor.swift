import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

@MainActor public final class UninstallerDescriptor: ModuleDescriptor {
    public static let id = ModuleID("uninstaller")
    public static let metadata = ModuleMetadata(
        id: id, name: UnStr.moduleName, summary: UnStr.summary,
        sfSymbol: "trash", permissions: [])
    public static let isolation: ModuleIsolation = .inProcess
    public static let category: ModuleCategory = .maintenance

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let ports = UninstallerSystemPorts(home: home)
        return UninstallerEngine(home: home, apps: ports.apps, fs: ports.fs,
                                 trash: ports.trash, running: ports.running)
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(UninstallerPanelTile()))
    }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(UninstallerSettingsPage(vm: vm))
    }
    // statusAppearance: default (.inactive) — not a toggle, never tints the menu bar.
}
