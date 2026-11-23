import SwiftUI

/// Shared panel visual language so every module's tile reads as one system:
/// a subtle card around the tile.
extension View {
    /// Wrap a module tile in the shared panel card.
    public func helmPanelCard() -> some View {
        self
            // The ladder's own «a card's inner padding», not a 12 of this file's:
            // it is what a 1×1 tile has left over for its words.
            .padding(HelmSpace.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HelmRadius.frame, style: .continuous)
                    .fill(HelmSurface.panelCardFill)
            )
    }
}
