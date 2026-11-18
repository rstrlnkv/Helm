import CoreGraphics

/// **What the UI does for the engine: the mask windows.** The engine decides which masks stand and whether they
/// are rounded; whoever implements this opens, moves and orders out the windows, and reads their layers back.
@MainActor public protocol CornerMasks: AnyObject {
    /// `added`: open a window, rounded. `changed`: resize, repath and recolour the same window.
    /// `removed`: order it out. Returns the window number of every mask now standing; a key absent has no window.
    func show(_ diff: MaskDiff) -> [MaskKey: Int]
    func setRounded(_ rounded: Bool, display: UInt32)
    /// Nil for a key with no window and for a window whose layer has not drawn: the engine does not correct
    /// the pointer there. Both reasons read the same on purpose.
    func presentation(of key: MaskKey) -> MaskPresentation?
    /// Idempotent.
    func removeAll()
}
