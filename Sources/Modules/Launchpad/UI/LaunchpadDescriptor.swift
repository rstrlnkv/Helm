import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Launchpad_Engine

/// The global shortcut's two names, in one place for the host's registration and the page's row. Both fail quietly when they drift.
enum LaunchpadHotkey {
    /// The slot `HotkeyManager` files the binding under. Not stored anywhere.
    static let open = "\(LaunchpadEngine.moduleID).open"

    /// Where the recorded combination is kept inside the module's store. **Deployed stored data: this name never moves.**
    static let storePrefix = "openHotkey"
}

@MainActor public final class LaunchpadDescriptor: ModuleDescriptor {
    public typealias Model = LaunchpadViewModel

    public static let id = ModuleID(LaunchpadEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: LpStr.moduleName, summary: LpStr.summary,
        sfSymbol: "square.grid.3x3", permissions: []) }
    public static let category: ModuleCategory = .utilities
    /// Violet, the hue no other module uses. White clears 6,5:1 on it, so the one literal serves
    /// the ordinary floor (3:1) and the increased-contrast one (4,5:1) in both appearances.
    public static let tint = ModuleTint(
        ordinary: (light: (0.467, 0.000, 1.000), dark: (0.467, 0.000, 1.000)),
        increasedContrast: (light: (0.467, 0.000, 1.000), dark: (0.467, 0.000, 1.000)))
    public static let glyph = ShellGlyph(
        body: ShellGlyph.box(3.5, 3.5, 17, 17, 4.5),
        detail: ShellGlyph.lines([8, 12, 16].flatMap { y in [8, 12, 16].map { x in ShellGlyph.dot(CGFloat(x), CGFloat(y)) } }))

    public init() {}

    public func makeModule(store: NamespacedStore) -> ModuleParts<LaunchpadViewModel> {
        let engine = LaunchpadEngine()
        let model = LaunchpadViewModel(work: engine, store: store)
        model.present = { model in
            LaunchpadWindow(model: model)
        }
        return ModuleParts(engine: engine, model: model)
    }

    /// No default combination: the shortcut holds nothing until the person records one.
    public static var hotkeys: [ModuleHotkey] { [ModuleHotkey(slot: LaunchpadHotkey.open, prefix: LaunchpadHotkey.storePrefix)] }

    public func hotkeyPressed(_ hotkey: ModuleHotkey, _ model: LaunchpadViewModel) { model.toggleLaunchpad() }

    /// Closes the model; the host calls it before the engine's `deactivate()`, on the person's switch and on quit.
    public func stop(_ model: LaunchpadViewModel) { model.stop() }

    public func menuBar(_ model: LaunchpadViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ model: LaunchpadViewModel) -> AnyView {
        AnyView(LaunchpadSettingsPage(lvm: model))
    }
}
