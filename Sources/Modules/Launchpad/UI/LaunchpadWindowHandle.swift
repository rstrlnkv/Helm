import Foundation

/// The one window the model opens, as the model sees it: present it, close it, bring it forward, hear that it closed.
/// A seam, so the model's door is tested without a screen; the window is the module's own panel (`LaunchpadWindow`).
@MainActor protocol LaunchpadWindowHandle: AnyObject {
    /// Called once when the window has closed, whoever closed it; the model forgets the window then.
    var onClose: (@MainActor () -> Void)? { get set }
    /// Orders the window front; the model has set `onClose` before.
    func present()
    func close()
    func bringForward()
}
