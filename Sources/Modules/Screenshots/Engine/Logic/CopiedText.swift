import Foundation

/// The text "Copy Text" puts on the clipboard: the lines the reader gave, **in the order it gave them**, one to
/// a line. The reader's order is the reading order (`ScreenTextReading`): it knows columns, and sorting the lines
/// by where they sit would interleave two columns that it kept apart. A line with nothing in it a person can see
/// (`AnnotationText.isInvisible`, the Text tool's own rule: blanks, controls, zero-width and format characters) is
/// left out, and nothing at all to copy is nil, which is "no text was found" and never an empty clipboard.
///
/// **Text the person covered is not copied.** The reading is of the frame without the layers, so the words under a
/// blur, a filled rectangle or ellipse, or a step's circle are in it, and a copy that put them on the clipboard
/// under «Text copied» would undo the cover. A line whose box lies wholly **or partly** under one of those layers
/// is left out (`lines(_:source:notUnder:)`): more is left out than is hidden, never less, and a layer's box is the
/// rectangle round it, an ellipse's corners included. A line the picture has no place for is kept: nothing says it is
/// covered. A copy of an area whose every line is covered says "no text was found".
public enum CopiedText {
    /// The layers that hide what is under them from a person looking at the picture.
    static func hides(_ layer: Annotation) -> Bool {
        switch layer.tool {
        case .blur, .step: true
        case .rectangle, .ellipse: layer.style.filled
        default: false
        }
    }

    /// `lines` without those whose box meets a layer that hides (`hides`).
    public static func lines(_ lines: [RecognizedLine], source: RecognizedBoxes.Source,
                             notUnder layers: [Annotation]) -> [RecognizedLine] {
        let covers = layers.filter(hides).map(\.frame)
        guard !covers.isEmpty else { return lines }
        return lines.filter { line in
            guard let ink = RecognizedBoxes.ink(of: line.box, in: source) else { return true }
            return !covers.contains { $0.intersects(ink) }
        }
    }

    public static func text(of lines: [RecognizedLine]) -> String? {
        let kept = lines.map(\.string).filter { !$0.allSatisfy(AnnotationText.isInvisible) }
        return kept.isEmpty ? nil : kept.joined(separator: "\n")
    }
}
