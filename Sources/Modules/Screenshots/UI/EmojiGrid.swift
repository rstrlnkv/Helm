import SwiftUI
import HelmUI
import Module_Screenshots_Engine

/// What the emoji grid shows, and where a click on a cell goes: back out through `pick`, which the overlay sends into its one door as
/// `EditorAction.pickEmoji`.
@MainActor final class EmojiGridModel: ObservableObject {
    /// The emoji the next click on the picture places; nil until one is picked.
    @Published private(set) var chosen: String?
    var pick: (String) -> Void = { _ in }

    /// A value the grid already shows is not published again: the overlay renders on every pointer move.
    func show(chosen: String?) { if self.chosen != chosen { self.chosen = chosen } }
}

/// The grid of the Emoji tool, on glass inside the overlay's panel: `EmojiSet.all`, `EmojiSet.perRow` to a row, each cell a `GlassCell`
/// named by the emoji itself, which is what VoiceOver reads and the tooltip says. It stands above the palette (below it where a pop-over stands
/// above the palette or there is no room above), is hosted by `EditorBarHostingView` and so takes the very first click, and never takes the keyboard. The system's
/// character palette is not used: from Helm it does not open (`Sources/Modules/Layout/UI/EmojiPalette.swift`).
struct EmojiGrid: View {
    @ObservedObject var model: EmojiGridModel

    /// A cell's side: `HelmSpace.s7` and `s2` (28 + 4).
    private static let cell: CGFloat = HelmSpace.s7 + HelmSpace.s2
    /// The emoji in it, 20 points: no step of the ladder has it.
    private static let glyph: CGFloat = 20

    var body: some View {
        let rows = stride(from: 0, to: EmojiSet.all.count, by: EmojiSet.perRow).map {
            Array(EmojiSet.all[$0..<min($0 + EmojiSet.perRow, EmojiSet.all.count)])
        }
        VStack(spacing: HelmSpace.s2) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: HelmSpace.s2) {
                    ForEach(row, id: \.self) { emoji in
                        GlassCell(name: emoji, selected: model.chosen == emoji, look: .plain, width: Self.cell, height: Self.cell) {
                            model.pick(emoji)
                        } icon: {
                            Text(emoji).font(.system(size: Self.glyph))
                        }
                    }
                }
            }
        }
        .padding(HelmSpace.s4)
        .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.frame))
    }
}
