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
    public static func color(token: String?) -> Color {
        guard let token, let p = PaletteColor(rawValue: token) else { return .white }
        return p.color
    }
}
