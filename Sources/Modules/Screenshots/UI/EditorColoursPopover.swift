import SwiftUI
import HelmUI
import Module_Screenshots_Engine

/// The colours pop-over, under the palette's colour wheel: all eight inks in two rows of four, on the card, glass and
/// reveal of `popoverCard` that the thickness and opacity pop-over wears. A swatch sends `.color`, the one colour every
/// tool shares, and the overlay closes the pop-over on the pick. No frame of `palette-frames/` draws it: the order is the
/// spectrum `AnnotationColor` lists, and it is `inks` alone that says so.
struct EditorColoursPopover: View {
    @ObservedObject var model: EditorBarModel
    /// The card's measured height; nil lays it out whole, as the thickness pop-over's does.
    var height: CGFloat?

    init(model: EditorBarModel, height: CGFloat? = nil) {
        self.model = model
        self.height = height
    }

    /// Read left to right, then down.
    static let inks: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]

    private static let perRow = 4

    var body: some View {
        VStack(spacing: HelmSpace.s4) {
            ForEach(0..<(Self.inks.count / Self.perRow), id: \.self) { row in
                HStack(spacing: HelmSpace.s4) {
                    ForEach(Self.inks[row * Self.perRow..<(row + 1) * Self.perRow], id: \.self) { ink in
                        EditorSwatch(color: ink, selected: model.lit == ink) { model.perform(.color(ink)) }
                    }
                }
            }
        }
        .padding(.horizontal, HelmSpace.s5 + HelmSpace.s1)
        .padding(.vertical, HelmSpace.s5 + HelmSpace.s1)
        .popoverCard(height: height, open: model.coloursOpen)
    }
}

extension EditorBarModel {
    /// The colour wheel's layout frame in the palette's own top-left points, like `moreFrame`.
    var wheelFrame: CGRect { colourCell }
}
