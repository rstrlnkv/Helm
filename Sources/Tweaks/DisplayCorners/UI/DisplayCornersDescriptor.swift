import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Tweak_DisplayCorners_Engine

/// What the card draws from. Empty until the card has settings to show.
@MainActor public final class DisplayCornersModel {
    public init() {}
}

/// Display Corners as the Tweaks page knows it: a name, a glyph, a sentence, and a card that has nothing under its header yet.
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
        ModuleParts(engine: DisplayCornersEngine(), model: DisplayCornersModel())
    }

    public func card(_ model: DisplayCornersModel) -> AnyView { AnyView(EmptyView()) }

    public func stop(_ model: DisplayCornersModel) {}
}
