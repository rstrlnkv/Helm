import AppKit

/// The icons one window draws, kept for as long as the window is open and not a moment longer.
///
/// Not `AppInfo.icon(forFile:)`, which is one cache for the whole process and never emptied: a grid of three hundred
/// apps would stay in memory after it was closed. This cache is the window state's own, bounded to what the live pages
/// and an open folder draw, and goes with the state. Only a page that is live asks.
final class LaunchpadIcons {
    private let cache = NSCache<NSString, NSImage>()
    private let size: CGFloat

    init(capacity: Int, size: CGFloat) {
        self.size = size
        cache.countLimit = 3 * capacity + capacity
    }

    func icon(for path: String) -> NSImage {
        if let kept = cache.object(forKey: path as NSString) { return kept }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: size, height: size)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}
