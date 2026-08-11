import SwiftUI

/// Shared panel visual language so every module's tile reads as one system:
/// a colored rounded-square icon badge + a subtle card.
/// The panel's module tile. Kept as its own name because that is what the
/// modules call it; it is `HelmIconPlate` at panel size, so the radius, the
/// glyph proportion and the shadow are the app's, not this file's.
struct HelmIconBadge: View {
    let symbol: String
    let color: Color
    var active: Bool

    init(symbol: String, color: Color, active: Bool = true) {
        self.symbol = symbol; self.color = color; self.active = active
    }

    var body: some View {
        HelmIconPlate(symbol: symbol, tint: color, size: 26, active: active)
            .accessibilityHidden(true)
    }
}

public extension View {
    /// Wrap a module tile in the shared panel card.
    func helmPanelCard() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(HelmSurface.panelCardFill)
            )
    }
}
