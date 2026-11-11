import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

@MainActor public final class ScreenshotsDescriptor: ModuleDescriptor {
    public static let id = ModuleID(ScreenshotsEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: ScStr.moduleName, summary: ScStr.summary,
        sfSymbol: "camera.viewfinder", permissions: [.screenRecording],
        // Without the grant a freeze is a desktop with no windows in it, and the
        // module can do nothing at all.
        inertWithout: [.screenRecording]) }
    public static let category: ModuleCategory = .utilities
    // Olive, the one hue the others left open: 0,34 from the nearest of them in
    // sRGB, where the floor is 0,15, and white reads 4,86:1 on it — past the
    // higher floor as well, so the two sets and the two appearances share one
    // value. Found by a search over the hue wheel for the largest distance
    // at a contrast of at least 4,55:1.
    public static let tint = ModuleTint(
        ordinary: (light: (0.384, 0.480, 0.000), dark: (0.384, 0.480, 0.000)),
        increasedContrast: (light: (0.384, 0.480, 0.000), dark: (0.384, 0.480, 0.000)))
    public static let glyph = ShellGlyph(
        body: ShellGlyph.box(3, 7.5, 18, 12.5, 3.5),
        extra: {
            var bump = Path()
            bump.move(to: ShellGlyph.pt(8.5, 7.5))
            bump.addLine(to: ShellGlyph.pt(9.6, 5.3))
            bump.addQuadCurve(to: ShellGlyph.pt(10.9, 4.5), control: ShellGlyph.pt(10, 4.5))
            bump.addLine(to: ShellGlyph.pt(13.1, 4.5))
            bump.addQuadCurve(to: ShellGlyph.pt(14.4, 5.3), control: ShellGlyph.pt(14, 4.5))
            bump.addLine(to: ShellGlyph.pt(15.5, 7.5))
            return bump
        }(),
        detail: ShellGlyph.circle(12, 13.7, 3))

    public init() {}

    public func makeModule(store: NamespacedStore) -> ModuleParts<ScreenshotsViewModel> {
        let engine = ScreenshotsEngine()
        return ModuleParts(engine: engine, model: ScreenshotsViewModel(work: engine, store: store))
    }

    /// The host closes the model before the engine goes: its stream ends and the capture
    /// in flight, its panels and its pins close with it.
    public func stop(_ model: ScreenshotsViewModel) { model.stop() }

    public func menuBar(_ model: ScreenshotsViewModel) -> MenuBarContribution? { .utility }

    public static var hotkeys: [ModuleHotkey] {
        ScreenshotsHotkey.allCases.map {
            ModuleHotkey(slot: $0.slot, prefix: $0.storePrefix, fallback: $0.fallback)
        }
    }

    /// The action lands in this target, which holds the overlay: a capture is
    /// tens of megabytes of frame, and a frame does not cross to the engine.
    public func hotkeyPressed(_ hotkey: ModuleHotkey, _ model: ScreenshotsViewModel) {
        guard let shot = ScreenshotsHotkey.allCases.first(where: { $0.slot == hotkey.slot }) else { return }
        model.press(shot)
    }

    public func settingsPage(_ model: ScreenshotsViewModel) -> AnyView {
        AnyView(ScreenshotsSettingsPage(model: model))
    }
}
