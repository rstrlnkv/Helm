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

    /// Every app the lists window draws a row for: the person's own rules, plus
    /// the built-in refusals this Mac actually has.
    ///
    /// **One expression, because the row that opens the window carries a count
    /// of what is inside it.** The page counted the rules table alone, so it
    /// said «No apps» over a list of seven and «1 app» over a list of eight —
    /// and the page's own doc says a count is the one thing a list behind a
    /// button owes. The built-ins are drawn as ordinary rows on purpose: a
    /// refusal the person cannot see is a refusal they cannot overrule.
    ///
    /// `builtIn` is passed rather than read from `blockedByDefault` because the
    /// caller has already filtered it to the applications installed here — a
    /// row for software nobody has is a list of somebody else's Mac.
    public static func listed(rules: [String: Bool], builtIn: [String]) -> Set<String> {
        Set(rules.keys).union(builtIn)
    }

    func allows(_ bundleID: String) -> Bool {
        // Nowhere to type is not somewhere safe to type.
        guard !bundleID.isEmpty else { return false }
        if let explicit = rules[bundleID] { return explicit }
        return !Self.blockedByDefault.contains(bundleID)
    }
}
