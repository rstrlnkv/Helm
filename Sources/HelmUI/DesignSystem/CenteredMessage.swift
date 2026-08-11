import SwiftUI

/// Vertically centred content filling its container — the shape every module's
/// empty/loading/placeholder state uses, so they all read the same.
struct HelmCenteredContent<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(spacing: spacing) {
            Spacer()
            content
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
