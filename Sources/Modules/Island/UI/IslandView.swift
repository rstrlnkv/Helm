import SwiftUI
import Module_Island_Engine

/// SwiftUI content of the island window. Top-pinned; the black shape grows
/// from a capsule hugging the notch (peek) to a card hanging below it
/// (expanded). The window frame is static — only this view animates.
struct IslandView: View {
    @ObservedObject var model: IslandModel
    /// Injected by the descriptor: shelf content inside the card.
    var content: AnyView = AnyView(EmptyView())

    var body: some View {
        ZStack(alignment: .top) {
            // Tap-away collapses while expanded (the window is ordered out in
            // hidden state, so this never blocks clicks when idle).
            if model.state == .expanded {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { model.dismiss() }
            }
            if model.state != .hidden {
                islandShape
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.28), value: model.state)
        .animation(.easeInOut(duration: 0.2), value: model.receivingDrag)
    }

    private var expanded: Bool { model.state == .expanded }

    private var islandShape: some View {
        VStack(spacing: 0) {
            if expanded {
                content
                    .frame(width: cardWidth - 32)
                    .padding(.top, 34)      // clears the physical notch strip
                    .padding(.bottom, 16)
            } else {
                // Peek: event line rendered BELOW the physical notch strip.
                HStack(spacing: 6) {
                    if let symbol = model.eventSymbol {
                        Image(systemName: symbol).font(.caption)
                    }
                    if let text = model.eventText {
                        Text(text).font(.caption)
                    }
                }
                .foregroundStyle(.white)
                .padding(.top, model.notchHeight + 2)
                .padding(.bottom, 7)
            }
        }
        .frame(width: expanded ? cardWidth : model.notchWidth + 24)
        .compositingGroup()
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 22, bottomTrailing: 22),
                                   style: .continuous)
                .fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
                .overlay(
                    UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 22, bottomTrailing: 22),
                                           style: .continuous)
                        .strokeBorder(model.receivingDrag ? Color.accentColor : Color.white.opacity(0.12),
                                      lineWidth: model.receivingDrag ? 2 : 1)
                )
        )
        .clipped()
    }

    private var cardWidth: CGFloat { model.notchWidth + 260 }
}
