import Foundation

/// Security-scoped bookmark IO, faked in tests.
public protocol BookmarkPort: Sendable {
    func make(_ url: URL) -> Data?
    /// nil = the file is gone (bookmark no longer resolves).
    func resolve(_ data: Data) -> URL?
}
