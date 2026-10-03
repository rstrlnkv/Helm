import Foundation

/// The emoji the editor's grid offers, and what `isOne` takes for one: one grapheme that leaves ink. The grid draws `all` in this order, left to right and down;
/// every entry is one grapheme that draws in colour, and a test holds the set to both.
public enum EmojiSet {
    /// Marks a person puts on a picture: yes and no, look here, praise, a warning, a face for what is funny, odd or wrong. One emoji
    /// presentation each, no skin tone and no joined family, so the set draws alike on every Mac that has the font.
    public static let all: [String] = [
        "👍", "👎", "👌", "👀", "👉", "👆", "✅", "❌",
        "❗", "❓", "⚠️", "⭐", "❤️", "🔥", "🎉", "💡",
        "😀", "😂", "😍", "🤔", "😮", "😢", "😡", "🙏",
    ]

    /// How many cells a row of the grid holds.
    public static let perRow = 8

    /// Whether `text` is exactly one grapheme within `AnnotationText.maxScalarsPerGrapheme` that leaves ink when it is drawn as an emoji
    /// layer: the one test `AnnotationEditing.place(emoji:at:style:)` asks of whatever it is given, a pick from the grid or not.
    public static func isOne(_ text: String) -> Bool {
        text.count == 1 && AnnotationText.fits(text) && AnnotationText.hasInk(text, tool: .emoji)
    }
}
