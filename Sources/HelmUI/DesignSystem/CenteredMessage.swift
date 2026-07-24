import SwiftUI

/// Vertically centred content filling its container — the shape every module's
/// empty/loading/placeholder state uses, so they all read the same.
public struct HelmCenteredContent<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: spacing) {
            Spacer()
            content
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public extension View {
    /// Convenience for the common "one secondary line, centred" empty state.
    static func helmCenteredMessage(_ text: String) -> some View {
        HelmCenteredContent {
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}
