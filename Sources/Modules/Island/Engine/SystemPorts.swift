import Foundation

/// Real bookmark IO. The app is not sandboxed, so plain bookmarks suffice —
/// they survive file moves and renames, unlike raw paths.
public struct FileBookmarkPort: BookmarkPort {
    public init() {}

    public func make(_ url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
