import AppKit
import Tweak_DisplayCorners_Engine
import HelmRuntime

/// **The mask windows of Display Corners, kept by key.** What the engine's `CornerMasks` asks for, done with
/// one `CornerMaskWindow` per `MaskKey`: a key never has two windows, a changed spec moves the window it has,
/// and `removeAll` is safe any number of times (the model's `stop()`, the engine's own `stop()` and a sleep
/// all reach it).
///
/// A mask whose shield is missing is still drawn, without protection from screenshots, and the log says so
/// once for this object: the shield's frame is built once for the process, so a failure would repeat for every mask.
@MainActor final class CornerMaskWindows: CornerMasks {
    private var windows: [MaskKey: CornerMaskWindow] = [:]
    private var saidNoShield = false

    /// Removed, then changed, then added. A changed key with no window is opened, an added key that already
    /// has one is changed, so the answer holds one window per key whatever the engine says.
    func show(_ diff: MaskDiff) -> [MaskKey: Int] {
        for key in diff.removed { windows.removeValue(forKey: key)?.tearDown() }
        for spec in diff.changed + diff.added {
            if let window = windows[spec.key] {
                window.apply(spec)
            } else {
                let window = CornerMaskWindow(spec: spec)
                windows[spec.key] = window
                if !window.maskView.hasShield, !saidNoShield {
                    saidNoShield = true
                    HelmLog.shared.warn(DisplayCornersEngine.moduleID, "capture shield unavailable; the masks will show in screenshots")
                }
                window.orderFrontRegardless()
            }
        }
        return windows.mapValues(\.windowNumber)
    }

    func setRounded(_ rounded: Bool, display: UInt32) {
        for (key, window) in windows where key.display == display { window.maskView.morph(toRounded: rounded) }
    }

    func presentation(of key: MaskKey) -> MaskPresentation? { windows[key]?.maskView.presentation }

    func removeAll() {
        let standing = windows
        windows = [:]
        for window in standing.values { window.tearDown() }
    }

    isolated deinit { removeAll() }
}
