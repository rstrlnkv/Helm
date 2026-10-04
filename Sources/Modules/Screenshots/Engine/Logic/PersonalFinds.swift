import CoreGraphics
import Foundation

/// What "Blur Emails and Phone Numbers" blurs, from a reading of the picture: an e-mail address, a phone number,
/// a card number by Helm's own rule (`CardNumbers`) and a link, **and nothing else — that list is the whole of
/// it,** and the menu item's hint names exactly it. A postal address is not on it, and neither is a name or a
/// face: what the system finds of those was not measured in every language, and the item does not promise it.
///
/// A find is one box to blur (`RecognizedBoxes.place`), and the boxes are made for `AnnotationEditing.insert(blurs:)`,
/// which puts each in as an ordinary blur layer the person can see, move and delete. Two kinds of find are not
/// made:
/// - **One wholly under a blur already placed that is coarse enough.** The text's own box lies inside a blur layer
///   of the picture whose block is at least the block this find would get (`RecognizedBoxes.step(forTextHeight:)`),
///   so a second pass over the same picture adds nothing and a find already covered is not covered twice. A blur
///   whose blocks are lower than the text is no cover: the text can be read back out of it, and the find is
///   blurred again at the step it needs.
/// - **One lying wholly inside another find of the same reading.** A card number that the system also reads as a
///   phone number is one place, not two; of two equal places the first stays.
///
/// The strings of the reading are not looked at here: only where the matches are.
public enum PersonalFinds {
    /// The ceiling on boxes from one reading: a picture of a long list of links is no reason to put a thousand
    /// layers into one undo step.
    static let limit = 500

    public static func finds(in lines: [RecognizedLine], source: RecognizedBoxes.Source,
                             under layers: [Annotation]) -> [RecognizedBoxes.Placed] {
        // A thousandth of a pixel of slack: a blur made to the text's own box is that box up to the rounding of the sums.
        let slack = 0.001 / max(source.scale, 1)
        let covering = layers.filter { $0.tool == .blur }
            .map { (frame: $0.frame.insetBy(dx: -slack, dy: -slack), block: $0.blockPoints) }
        var candidates: [(ink: CGRect, placed: RecognizedBoxes.Placed)] = []
        for match in lines.flatMap(\.matches) {
            guard let ink = RecognizedBoxes.ink(of: match.box, in: source),
                  let placed = RecognizedBoxes.place(match.box, in: source)
            else { continue }
            let need = placed.step.points(for: .blur)
            if covering.contains(where: { $0.frame.contains(ink) && $0.block >= need }) { continue }
            candidates.append((ink, placed))
        }
        var kept: [RecognizedBoxes.Placed] = []
        for (index, candidate) in candidates.enumerated() {
            let inside = candidates.enumerated().contains { other, rival in
                guard other != index, rival.ink.contains(candidate.ink) else { return false }
                // Equal boxes: the earlier one stays.
                return rival.ink != candidate.ink || other < index
            }
            if !inside { kept.append(candidate.placed) }
            if kept.count == limit { break }
        }
        return kept
    }
}
