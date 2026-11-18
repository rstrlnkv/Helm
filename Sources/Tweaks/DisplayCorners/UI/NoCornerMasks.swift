import Tweak_DisplayCorners_Engine

/// **The masks of a tweak whose windows are not built yet.** It opens nothing, so the engine has no window to
/// sample and starts neither its ticker nor its pointer. The commit that adds the real mask windows deletes this file.
@MainActor final class NoCornerMasks: CornerMasks {
    func show(_ diff: MaskDiff) -> [MaskKey: Int] { [:] }
    func setRounded(_ rounded: Bool, display: UInt32) {}
    func presentation(of key: MaskKey) -> MaskPresentation? { nil }
    func removeAll() {}
}
