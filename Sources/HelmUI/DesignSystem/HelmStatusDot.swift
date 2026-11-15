import SwiftUI

/// The shared "connected / not" indicator dot.
///
/// In `HelmSignal.success` rather than `Color.green` (2.22:1 against the window in light appearance)
/// because its colour *is* its entire message.
public struct HelmStatusDot: View {
    /// `.row` beside a name in a row, `.widget` in a panel tile's header.
    public enum Size {
        case row, widget
        var side: CGFloat { self == .row ? 8 : 6 }
    }

    let active: Bool
    let size: Size
    @Environment(\.helmTraits) private var traits
    public init(active: Bool, size: Size = .row) {
        self.active = active
        self.size = size
    }
    public var body: some View {
        Circle()
            .fill(active ? HelmSignal.success(increased: traits.increasedContrast) : Color.secondary.opacity(0.4))
            .frame(width: size.side, height: size.side)
            .accessibilityHidden(true)
    }
}
