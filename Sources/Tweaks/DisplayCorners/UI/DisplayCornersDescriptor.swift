import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Tweak_DisplayCorners_Engine

/// What the card draws from: the engine's last state, and the tweak's own end.
///
/// The stream is taken in `init`, before the host calls `activate()`, so the first state is not missed; the task
/// that reads it is held and cancelled in `stop()`, which the host calls before the engine's `deactivate()`.
@MainActor public final class DisplayCornersModel {
    public private(set) var state: CornerState
    private let engine: DisplayCornersEngine
    private let masks: any CornerMasks
    private var reading: Task<Void, Never>?

    init(engine: DisplayCornersEngine, masks: any CornerMasks) {
        self.engine = engine
        self.masks = masks
        state = engine.state
        let states = engine.stream()
        reading = Task { [weak self] in
            for await next in states { self?.state = next }
        }
    }

    /// Idempotent: stops listening, ends a calibration preview and orders every mask out.
    func stop() {
        reading?.cancel()
        reading = nil
        engine.endCalibration()
        masks.removeAll()
    }
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
        let masks = CornerMaskWindows()
        let engine = DisplayCornersEngine(store: store, masks: masks)
        return ModuleParts(engine: engine, model: DisplayCornersModel(engine: engine, masks: masks))
    }

    public func card(_ model: DisplayCornersModel) -> AnyView { AnyView(EmptyView()) }

    public func stop(_ model: DisplayCornersModel) { model.stop() }
}
