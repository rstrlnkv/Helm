import Combine
import Foundation
import Tweak_DisplayCorners_Engine

/// What the model asks of the engine: the engine's state and stream, and its commands. A seam so a kept test can
/// stand a recording engine in for the real one; `DisplayCornersEngine` is the one conformer in the app.
@MainActor protocol CornerEngineSide: AnyObject {
    var state: CornerState { get }
    func stream() -> AsyncStream<CornerState>
    func setBuiltIn(_ on: Bool)
    func setExternal(_ on: Bool)
    func setPreset(points: Double)
    func stepRadius(direction: Int)
    func beginCalibration()
    func setCalibration(r: Double, g: Double, b: Double)
    func endCalibration()
}

extension DisplayCornersEngine: CornerEngineSide {}

/// The colour panel as the model uses it, a seam for the same reason: the live one is `NSColorPanel.shared`.
@MainActor protocol CalibrationPanelSeam: AnyObject {
    /// Shows the panel on `colour`; each colour picked goes to `onPick` as red, green and blue in sRGB, and `onClosed`
    /// is called when somebody closes the panel, never when `close()` does.
    func open(showing colour: CalibrationColour, title: String,
              onPick: @escaping (Double, Double, Double) -> Void, onClosed: @escaping () -> Void)
    /// Idempotent.
    func close()
}

/// What the card draws from: the engine's last state, and the tweak's own end.
///
/// **The state is adopted from the engine, never kept apart.** Every command is the engine's own and is followed at
/// once by `adopt(_:)` of `engine.state`, the colour panel's two callbacks included; opening the panel is no command
/// to the engine, so it adopts nothing (`chooseCalibrationColour`). The
/// stream adopts what the engine says on its own (a display change). An engine that is not active takes a switch,
/// a preset or a step as a write to its store only, and a calibration command as nothing, so what is adopted then is
/// the engine's state, not the command's. The model is
/// built before the host calls `activate()`, so its first state is the engine's empty one; the card adopts again
/// as it appears, so a switch should not show its old value for a frame (the first frame was seen right once; not
/// measured beyond that). The engine refuses
/// an equal colour and clamps a radius, and the model adds no second copy of either.
///
/// **The colour panel is owned here, not by a view.** `stop()` has to close it when the tweak goes off, and a
/// view-held opener would go with its page (`EditorColourPanel`'s reason: the panel holds its target weakly, so the
/// opener lives as long as whoever ends the panel). Calibration ends with the page: `pageLeft()`, which the card's
/// calibration row calls as it leaves the screen (`onDisappear`; whether it fires when the settings window is
/// closed or hidden has not been measured), closes the panel and ends it; the panel never holds it alone.
///
/// The stream is taken in `init`, before the host calls `activate()`, so the first state is not missed; the task
/// that reads it is held and cancelled in `stop()`, which the host calls before the engine's `deactivate()`.
@MainActor public final class DisplayCornersModel: ObservableObject {
    @Published private(set) var state: CornerState
    private let engine: any CornerEngineSide
    private let masks: any CornerMasks
    private let panel: any CalibrationPanelSeam
    private var reading: Task<Void, Never>?

    init(engine: any CornerEngineSide, masks: any CornerMasks, panel: any CalibrationPanelSeam) {
        self.engine = engine
        self.masks = masks
        self.panel = panel
        state = engine.state
        let states = engine.stream()
        reading = Task { [weak self] in
            for await next in states { self?.adopt(next) }
        }
    }

    isolated deinit { reading?.cancel() }

    /// The colour the masks are drawn in, or the one calibration starts from.
    var calibrationColour: CalibrationColour { state.calibrationColour ?? .default }

    func setBuiltIn(_ on: Bool) { engine.setBuiltIn(on); adopt() }

    func setExternal(_ on: Bool) { engine.setExternal(on); adopt() }

    func choosePreset(points: Int) { engine.setPreset(points: Double(points)); adopt() }

    func step(direction: Int) { engine.stepRadius(direction: direction); adopt() }

    /// On starts the preview; off closes the colour panel, then ends it.
    func setCalibrating(_ on: Bool) {
        if on {
            engine.beginCalibration()
        } else {
            panel.close()
            engine.endCalibration()
        }
        adopt()
    }

    /// Opens the colour panel; nothing while calibration is not running. It adopts nothing itself: the engine is
    /// reached, and adopted, only through the panel's `onPick` and `onClosed`.
    func chooseCalibrationColour() {
        guard state.calibrating else { return }
        panel.open(showing: calibrationColour, title: DisplayCornersStr.calibrationColour,
                   onPick: { [weak self] r, g, b in
                       guard let self else { return }
                       engine.setCalibration(r: r, g: g, b: b)
                       adopt()
                   },
                   onClosed: { [weak self] in
                       guard let self else { return }
                       engine.endCalibration()
                       adopt()
                   })
    }

    /// The card's own appearing: the engine's state as it is now.
    func adopt() { adopt(engine.state) }

    /// The Tweaks page has left the screen, or the settings window has: the panel is closed and calibration ends.
    /// Idempotent.
    func pageLeft() {
        panel.close()
        engine.endCalibration()
        adopt()
    }

    /// Idempotent: stops listening, closes the colour panel, ends a calibration preview and orders every mask out.
    func stop() {
        reading?.cancel()
        reading = nil
        panel.close()
        engine.endCalibration()
        adopt()
        masks.removeAll()
    }

    private func adopt(_ next: CornerState) {
        if next != state { state = next }
    }
}
