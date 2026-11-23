import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Tweak_DisplayCorners_Engine

/// Display Corners as the Tweaks page knows it: a name, a glyph, a sentence, and the rows of its card.
@MainActor public final class DisplayCornersDescriptor: TweakDescriptor {
    public static let id = ModuleID(DisplayCornersEngine.moduleID)
    public static var name: String { DisplayCornersStr.name }
    public static var summary: String { DisplayCornersStr.summary }
    /// A display with its corners well rounded, and its stand.
    public static let glyph = ShellGlyph(
        body: ShellGlyph.box(3, 4, 18, 13, 5),
        extra: ShellGlyph.lines([[ShellGlyph.pt(9, 20.5), ShellGlyph.pt(15, 20.5)]]))

    public init() {}

    public func makeTweak(store: NamespacedStore) -> ModuleParts<DisplayCornersModel> {
        let masks = CornerMaskWindows()
        let engine = DisplayCornersEngine(store: store, masks: masks)
        return ModuleParts(engine: engine, model: DisplayCornersModel(engine: engine, masks: masks, panel: CalibrationColourPanel()))
    }

    public func rows(_ model: DisplayCornersModel) -> [AnyView] { DisplayCornersCard.rows(model) }

    public func stop(_ model: DisplayCornersModel) { model.stop() }
}
