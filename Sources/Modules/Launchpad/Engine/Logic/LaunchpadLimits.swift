/// **One set of ceilings for everything Launchpad reads from outside** — the layout file
/// and the installed-apps walk — so a planted or runaway input is bounded the same way
/// wherever it enters. A count above its ceiling is truncated, never a trap.
enum LaunchpadLimits {
    /// A layout file larger than this is unreadable; checked before decoding.
    static let maxFileBytes = 2 * 1024 * 1024
    static let maxApps = 10_000
    static let maxItems = 5_000
    static let maxFolderApps = 1_000
    /// Bundle ids, names and folder names read from a file or a property list.
    static let maxStringLength = 255
    static let maxFolderName = 64
    /// Directory levels walked below a root; an `.app` directly in the root is level 0.
    static let maxDepth = 2

    static func bounded(_ s: String) -> String {
        s.count > maxStringLength ? String(s.prefix(maxStringLength)) : s
    }
}
