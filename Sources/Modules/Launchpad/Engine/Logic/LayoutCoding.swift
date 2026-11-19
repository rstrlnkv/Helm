import Foundation

/// **The layout file, bounded.** JSON `version: 1`; a version above the known is unreadable
/// (an older build must not rewrite a newer one's file); every field read
/// leniently; counts truncated to `LaunchpadLimits`; a folder id that is not a UUID gets a fresh one.
/// A page break is one more kind of entry, `{"pageBreak": true}`, so a file without one decodes as it always did
/// and the version stays 1; an older build skips the entry it does not know, and so loses the page it stood for.
extension LaunchpadLayout: Codable {
    static let version = 1

    private enum Keys: String, CodingKey { case version, items, hidden }
    private enum ItemKeys: String, CodingKey { case app, folder, pageBreak }
    private enum FolderKeys: String, CodingKey { case id, name, apps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version <= Self.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "newer than known")
        }
        var items: [Item] = []
        if var list = try? c.nestedUnkeyedContainer(forKey: .items) {
            while !list.isAtEnd, items.count < LaunchpadLimits.maxItems {
                // A failed decode leaves the cursor where it was; a decode that succeeded has moved it.
                if let entry = try? list.decode(Entry.self) { if let item = entry.item { items.append(item) } }
                else { _ = try? list.decode(Skip.self) }
            }
        }
        var hidden: Set<AppID> = []
        if var list = try? c.nestedUnkeyedContainer(forKey: .hidden) {
            while !list.isAtEnd, hidden.count < LaunchpadLimits.maxApps {
                if let id = try? list.decode(String.self) { hidden.insert(LaunchpadLimits.bounded(id)) }
                else { _ = try? list.decode(Skip.self) }
            }
        }
        self.init(items: items, hidden: hidden)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(Self.version, forKey: .version)
        try c.encode(items.map(Entry.init), forKey: .items)
        try c.encode(hidden.sorted(), forKey: .hidden)
    }

    /// Consumes one element of any shape so a bad entry does not stop the list.
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

    private struct Entry: Codable {
        let item: Item?

        init(_ item: Item) { self.item = item }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: ItemKeys.self)
            if let id = try? c.decode(String.self, forKey: .app) {
                item = .app(LaunchpadLimits.bounded(id))
            } else if let f = try? c.nestedContainer(keyedBy: FolderKeys.self, forKey: .folder) {
                let id = (try? f.decode(String.self, forKey: .id)).flatMap(UUID.init(uuidString:)) ?? UUID()
                let name = LaunchpadLimits.bounded((try? f.decode(String.self, forKey: .name)) ?? "")
                var apps: [AppID] = []
                if var list = try? f.nestedUnkeyedContainer(forKey: .apps) {
                    while !list.isAtEnd, apps.count < LaunchpadLimits.maxFolderApps {
                        if let a = try? list.decode(String.self) { apps.append(LaunchpadLimits.bounded(a)) }
                        else { _ = try? list.decode(Skip.self) }
                    }
                }
                item = .folder(Folder(id: id, name: String(name.prefix(LaunchpadLimits.maxFolderName)), apps: apps))
            } else if (try? c.decode(Bool.self, forKey: .pageBreak)) == true {
                item = .pageBreak
            } else {
                item = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: ItemKeys.self)
            switch item {
            case .app(let id): try c.encode(id, forKey: .app)
            case .folder(let f):
                var n = c.nestedContainer(keyedBy: FolderKeys.self, forKey: .folder)
                try n.encode(f.id.uuidString, forKey: .id)
                try n.encode(f.name, forKey: .name)
                try n.encode(f.apps, forKey: .apps)
            case .pageBreak: try c.encode(true, forKey: .pageBreak)
            case nil: break
            }
        }
    }
}
