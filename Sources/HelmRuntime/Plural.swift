import Foundation

/// Counted nouns. Interpolating a number in front of a fixed word produces
/// "Переместить 3 объектов" in Russian and "Move 1 items" in English; both
/// read as a bug to the person looking at the dialog.
public enum Plural {
    /// "3 объекта", "1 item" — the generic noun Helm counts in confirmations.
    public static func items(_ count: Int, language: String) -> String {
        switch language {
        case "ru": return "\(count) " + russian(count, "объект", "объекта", "объектов")
        case "es": return "\(count) " + (count == 1 ? "elemento" : "elementos")
        case "fr": return "\(count) " + (count <= 1 ? "élément" : "éléments")
        case "de": return "\(count) " + (count == 1 ? "Objekt" : "Objekte")
        case "pt": return "\(count) " + (count == 1 ? "item" : "itens")
        case "ja": return "\(count) 項目"
        case "zh": return "\(count) 个项目"
        default: return "\(count) " + (count == 1 ? "item" : "items")
        }
    }

    /// Russian picks its form from the last two digits: 11–14 always take the
    /// "many" form, whatever their final digit says.
    public static func russian(_ count: Int, _ one: String, _ few: String,
                               _ many: String) -> String {
        let magnitude = abs(count)
        if (11...14).contains(magnitude % 100) { return many }
        switch magnitude % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
