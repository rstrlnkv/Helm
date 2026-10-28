import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

@MainActor public final class UninstallerDescriptor: ModuleDescriptor {
    public static let id = ModuleID(UninstallerEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: UnStr.moduleName, summary: UnStr.summary,
        sfSymbol: "trash", permissions: [.fullDisk]) }
    public static let category: ModuleCategory = .files
    public static let tint = ModuleTint(
        ordinary: (light: (1.000, 0.220, 0.235), dark: (1.000, 0.259, 0.271)),
        increasedContrast: (light: (0.878, 0.193, 0.206), dark: (0.859, 0.222, 0.233)))
    public static let glyph = ShellGlyph(
        body: {
            var bin = Path()
            bin.move(to: ShellGlyph.pt(6.2, 8))
            bin.addLine(to: ShellGlyph.pt(7, 18.3))
            bin.addQuadCurve(to: ShellGlyph.pt(9.4, 20.5), control: ShellGlyph.pt(7.2, 20.5))
            bin.addLine(to: ShellGlyph.pt(14.6, 20.5))
            bin.addQuadCurve(to: ShellGlyph.pt(17, 18.3), control: ShellGlyph.pt(16.8, 20.5))
            bin.addLine(to: ShellGlyph.pt(17.8, 8))
            bin.closeSubpath()
            return bin
        }(),
        extra: {
            var lid = ShellGlyph.lines([[ShellGlyph.pt(4, 8), ShellGlyph.pt(20, 8)]])
            lid.move(to: ShellGlyph.pt(9.5, 8))
            lid.addLine(to: ShellGlyph.pt(9.5, 6))
            lid.addQuadCurve(to: ShellGlyph.pt(11, 4.5), control: ShellGlyph.pt(9.5, 4.5))
            lid.addLine(to: ShellGlyph.pt(13, 4.5))
            lid.addQuadCurve(to: ShellGlyph.pt(14.5, 6), control: ShellGlyph.pt(14.5, 4.5))
            lid.addLine(to: ShellGlyph.pt(14.5, 8))
            return lid
        }())
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
