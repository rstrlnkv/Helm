import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

@MainActor public final class UninstallerDescriptor: ModuleDescriptor {
    public static let id = ModuleID(UninstallerEngine.moduleID)
    public static let metadata = ModuleMetadata(
        id: id, name: UnStr.moduleName, summary: UnStr.summary,
        sfSymbol: "trash", permissions: [.fullDisk])
    public static let category: ModuleCategory = .files
    public static let tint: ModuleTint = .uninstaller
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let ports = UninstallerSystemPorts(home: home)
        // The store the host hands every module was unused here until the Trash
        // offer needed somewhere to remember a "no" across launches.
        return UninstallerEngine(home: home, apps: ports.apps, fs: ports.fs,
                                 trash: ports.trash, running: ports.running,
                                 extensions: SystemExtensionLister(),
                                 store: store)
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(UninstallerSettingsPage(vm: vm))
    }
    // statusAppearance: default (.inactive) — not a toggle, never tints the menu bar.
}

/// The same, for the uninstaller.
public typealias UninstallerCommand = Module_Uninstaller_Engine.UninstallerCommand
/// So the host can say the event name instead of spelling it — the same
/// re-export the hotkeys already rely on for their command enums.
public typealias UninstallerEvent = Module_Uninstaller_Engine.UninstallerEvent
