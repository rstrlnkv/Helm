import SwiftUI
/// The fixed active-tint palette for status icons (Keep Awake picks from this).
public enum PaletteColor: String, CaseIterable, Sendable {
    case white, red, orange, yellow, green, mint, cyan, blue, purple, pink
    public var color: Color {
        switch self {
        case .white: return .white
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .cyan: return .cyan
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        }
    }
    /// The colour's name in the user's language. It was `rawValue.capitalized`
    /// — the one user-visible string in the app that skipped `L()` — and on a
    /// swatch the colour itself is the only other signal there is.
    public var label: String {
        switch self {
        case .white: return L("White", [.ru: "Белый", .es: "Blanco", .fr: "Blanc", .de: "Weiß", .ja: "白", .zh: "白色", .pt: "Branco"])
        case .red: return L("Red", [.ru: "Красный", .es: "Rojo", .fr: "Rouge", .de: "Rot", .ja: "赤", .zh: "红色", .pt: "Vermelho"])
        case .orange: return L("Orange", [.ru: "Оранжевый", .es: "Naranja", .fr: "Orange", .de: "Orange", .ja: "オレンジ", .zh: "橙色", .pt: "Laranja"])
        case .yellow: return L("Yellow", [.ru: "Жёлтый", .es: "Amarillo", .fr: "Jaune", .de: "Gelb", .ja: "黄", .zh: "黄色", .pt: "Amarelo"])
        case .green: return L("Green", [.ru: "Зелёный", .es: "Verde", .fr: "Vert", .de: "Grün", .ja: "緑", .zh: "绿色", .pt: "Verde"])
        case .mint: return L("Mint", [.ru: "Мятный", .es: "Menta", .fr: "Menthe", .de: "Mint", .ja: "ミント", .zh: "薄荷色", .pt: "Menta"])
        case .cyan: return L("Cyan", [.ru: "Голубой", .es: "Cian", .fr: "Cyan", .de: "Cyan", .ja: "シアン", .zh: "青色", .pt: "Ciano"])
        case .blue: return L("Blue", [.ru: "Синий", .es: "Azul", .fr: "Bleu", .de: "Blau", .ja: "青", .zh: "蓝色", .pt: "Azul"])
        case .purple: return L("Purple", [.ru: "Фиолетовый", .es: "Morado", .fr: "Violet", .de: "Violett", .ja: "紫", .zh: "紫色", .pt: "Roxo"])
        case .pink: return L("Pink", [.ru: "Розовый", .es: "Rosa", .fr: "Rose", .de: "Rosa", .ja: "ピンク", .zh: "粉色", .pt: "Rosa"])
        }
    }

    public static func color(token: String?) -> Color {
        guard let token, let p = PaletteColor(rawValue: token) else { return .white }
        return p.color
    }
}
