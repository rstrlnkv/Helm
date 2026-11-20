import Foundation
import Module_Launchpad_Engine

/// The one window the model opens, as the model sees it: present it, close it, bring it forward, hear that it closed, and
/// scrub it open or shut with the fingers. A seam, so the model's door is tested without a screen; the window is the module's
/// own panel (`LaunchpadWindow`).
@MainActor protocol LaunchpadWindowHandle: AnyObject {
    /// Called once when the window has closed, whoever closed it; the model forgets the window then.
    var onClose: (@MainActor () -> Void)? { get set }
    /// Orders the window front; the model has set `onClose` before.
    func present()
    func close()
    func bringForward()
    /// A scrub begins: a `.pinch` shows a window that is not yet open at progress 0 without making it key, a `.spread` takes the
    /// open window's picture from where it is. Then `scrub(to:)` follows the fingers, 0 to 1 of the gesture, and `endScrub` ends it.
    func beginScrub(_ direction: PinchDirection)
    func scrub(to progress: Double)
    /// `.complete` finishes what the fingers began (a pinch opens, a spread closes); `.revert` puts it back (a pinch's half-open
    /// window closes, a spread's half-closed one is whole again).
    func endScrub(_ outcome: PinchOutcome)
}
