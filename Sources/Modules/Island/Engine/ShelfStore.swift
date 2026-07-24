import Foundation
import HelmRuntime

public struct ShelfItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    /// nil while the bookmark doesn't resolve (file deleted or volume gone).
    public let url: URL?
    public let bookmark: Data
    public var missing: Bool { url == nil }
}

/// The island's file shelf: bookmark references only — files never move.
/// Persists through the module's `NamespacedStore`; newest items first.
@MainActor public final class ShelfStore {
    public private(set) var items: [ShelfItem] = []
    /// UI hook: called after any mutation.
    public var onChange: (() -> Void)?

    private let store: NamespacedStore
    private let bookmarks: BookmarkPort
    private let key = "shelfBookmarks"

    public init(store: NamespacedStore, bookmarks: BookmarkPort) {
        self.store = store
        self.bookmarks = bookmarks
        load()
    }

    public func add(_ urls: [URL]) {
        // The batch goes in front as a block, keeping the order the user dropped.
        var batch: [ShelfItem] = []
        for url in urls {
            guard !items.contains(where: { $0.url?.path == url.path }),
                  !batch.contains(where: { $0.url?.path == url.path }),
                  let data = bookmarks.make(url) else { continue }
            batch.append(ShelfItem(id: UUID(), name: url.lastPathComponent, url: url, bookmark: data))
        }
        items.insert(contentsOf: batch, at: 0)
        persist()
    }

    public func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    public func clear() {
        items.removeAll()
        persist()
    }

    // MARK: - Persistence (bookmarks as base64 strings)

    private func persist() {
        store.set(items.map { $0.bookmark.base64EncodedString() }, for: key)
        onChange?()
    }

    private func load() {
        items = store.stringArray(key).compactMap { encoded in
            guard let data = Data(base64Encoded: encoded) else { return nil }
            let url = bookmarks.resolve(data)
            // A dead bookmark still shows (greyed) — the name survives in the URL
            // path we encoded; without resolution fall back to a generic label.
            let name = url?.lastPathComponent
                ?? String(decoding: data, as: UTF8.self).split(separator: "/").last.map(String.init)
                ?? "?"
            return ShelfItem(id: UUID(), name: name, url: url, bookmark: data)
        }
    }
}
