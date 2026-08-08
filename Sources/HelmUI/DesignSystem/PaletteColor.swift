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
        case .white: return L("White")
        case .red: return L("Red")
        case .orange: return L("Orange")
        case .yellow: return L("Yellow")
        case .green: return L("Green")
        case .mint: return L("Mint")
        case .cyan: return L("Cyan")
        case .blue: return L("Blue")
        case .purple: return L("Purple")
        case .pink: return L("Pink")
        }
    }
}
