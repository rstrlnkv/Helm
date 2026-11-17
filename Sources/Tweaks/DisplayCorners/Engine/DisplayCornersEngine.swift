import HelmContract

/// Display Corners' engine: what lives outside Helm and the card needs to know.
///
/// **Empty on purpose, for now.** The frame of the Tweaks page lands first, with this pair as its
/// one tweak, so that the boundary checks and the page run over a real tweak rather than over
/// nothing. `activate()` will read the settings, decide the layout and start the display
/// sampling, the pointer tap and the pointer guard; `deactivate()` will stop all of it, in
/// the order `CGKeyTap` stops its own, and be safe to call twice.
public final class DisplayCornersEngine: ModuleEngine {
    /// This tweak's id, and the only place it is written down: it reaches disk in the
    /// `tweak.<id>` namespace of its store, so the descriptor builds its id from this.
    /// **The string never changes.**
    public static let moduleID = "display-corners"

    public init() {}

    public func activate() {}

    public func deactivate() {}
}
