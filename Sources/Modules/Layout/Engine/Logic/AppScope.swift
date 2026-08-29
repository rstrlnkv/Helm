import Foundation

/// Which apps take conversions.
///
/// Two kinds are refused before any rule is consulted: a terminal, where
/// `ghbdtn` is as likely to be a filename as a mistake, and a password manager,
/// where the text is not prose at all. The user can overrule both — it is their
/// machine — but not by accident.
public struct AppScope: Equatable, Sendable {
    /// bundle id → allowed. Absent means "no opinion".
    let rules: [String: Bool]

    public static let blockedByDefault: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.apple.keychainaccess",
    ]

    func allows(_ bundleID: String) -> Bool {
        // Nowhere to type is not somewhere safe to type.
        guard !bundleID.isEmpty else { return false }
        if let explicit = rules[bundleID] { return explicit }
        return !Self.blockedByDefault.contains(bundleID)
    }
}
