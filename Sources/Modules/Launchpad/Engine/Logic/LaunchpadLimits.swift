import HelmRuntime

/// **One set of ceilings for everything Launchpad reads from outside** — the layout file
/// and the installed-apps walk (bundle files are read at `PropertyListFile.byteCeiling`) — so a planted
/// or runaway input is bounded the same way wherever it enters. A count above its ceiling is truncated, never a trap.
enum LaunchpadLimits {
    /// A layout file larger than this is unreadable; checked before decoding.
    static let maxFileBytes = PropertyListFile.byteCeiling
    static let maxApps = 10_000
    static let maxItems = 5_000
    static let maxFolderApps = 1_000
    /// Pages a layout file may make by page breaks: one fewer breaks; a later break is dropped.
    static let maxPages = 200
    /// Bundle ids, names and folder names read from a file or a property list.
    static let maxStringLength = 255
    static let maxFolderName = 64
    /// Directory levels walked below a root; an `.app` directly in the root is level 0.
    static let maxDepth = 2
    /// A launch count above this reads as this: a file that says more is clamped, and `record` stops here.
    static let maxLaunchCount = 1_000_000
    /// Counted apps kept: a file holding more keeps the highest counts (ties by the smaller id).
    static let maxCountedApps = maxApps

    static func bounded(_ s: String) -> String {
        s.count > maxStringLength ? String(s.prefix(maxStringLength)) : s
    }
}
