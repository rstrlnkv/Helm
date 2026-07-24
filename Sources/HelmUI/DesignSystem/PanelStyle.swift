import SwiftUI

/// Shared panel visual language so every module's tile reads as one system:
/// a colored rounded-square icon badge + a subtle card.
public struct HelmIconBadge: View {
    let symbol: String
    let color: Color
    var active: Bool

    public init(symbol: String, color: Color, active: Bool = true) {
        self.symbol = symbol; self.color = color; self.active = active
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.secondary.opacity(0.45)))
            )
    }
}

public extension View {
    /// Wrap a module tile in the shared panel card.
    func helmPanelCard() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}
