import AppKit

/// The icons one window draws, kept for as long as the window is open and not a moment longer.
///
/// Not `AppInfo.icon(forFile:)`, which is one cache for the whole process and never emptied: a grid of three hundred
/// apps would stay in memory after it was closed. This cache is the window state's own, bounded to what the live pages
/// and an open folder's live pages draw, and goes with the state. Only a page that is live asks.
final class LaunchpadIcons {
    private let cache = NSCache<NSString, NSImage>()
    private var size: CGFloat

    init(capacity: Int, size: CGFloat) {
        self.size = size
        cache.countLimit = 6 * capacity
    }

    func icon(for path: String) -> NSImage {
        if let kept = cache.object(forKey: path as NSString) { return kept }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: size, height: size)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }

    /// The window has closed: nothing it drew stays.
    func removeAll() { cache.removeAllObjects() }

    /// A new grid: the cache's bound follows the page, and what was drawn at another size is dropped (an image keeps its point size).
    func reconfigure(capacity: Int, size: CGFloat) {
        cache.countLimit = 6 * capacity
        guard size != self.size else { return }
        self.size = size
        cache.removeAllObjects()
    }
}
