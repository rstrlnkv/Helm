import Foundation
import HelmRuntime

public typealias AppID = String

/// **What the person arranged: top-level items, folders, and hidden apps — by bundle id only.**
///
/// No path is stored: a path belongs to the latest catalog read, so a planted layout
/// file cannot make Helm launch an arbitrary one, and an app that moved keeps its place.
public struct LaunchpadLayout: Equatable, Sendable {
    public struct Folder: Equatable, Sendable {
        public internal(set) var id: UUID
        public internal(set) var name: String
        public internal(set) var apps: [AppID]
    }

    public enum Item: Equatable, Sendable {
        case app(AppID)
        case folder(Folder)
    }

    public internal(set) var items: [Item] = []
    public internal(set) var hidden: Set<AppID> = []

    static let empty = LaunchpadLayout()
}

/// One gesture, one case. A vanished id is refused (`applying` returns nil).
enum LaunchpadEdit: Equatable, Sendable {
    /// Top-level reorder; the index is clamped.
    case move(String, toIndex: Int)
    /// The folder takes the target's slot, apps `[target, dropped]`; the name is passed in, the engine holds no strings.
    case makeFolder(drop: AppID, onto: AppID, name: String)
    case add(AppID, toFolder: UUID, at: Int?)
    /// Lands right after the folder.
    case remove(AppID, fromFolder: UUID)
    case moveInFolder(AppID, toIndex: Int)
    case rename(UUID, to: String)
    case hide(AppID)
    case unhide(AppID)
    /// Order and folders go; hidden stays. The engine reconciles the result, which puts every shown app back in catalog order.
    case resetArrangement
}

extension LaunchpadLayout.Item {
    /// An app's id, or a folder's UUID string.
    public var itemID: String {
        switch self {
        case .app(let id): id
        case .folder(let f): f.id.uuidString
        }
    }
}

extension LaunchpadLayout {

    /// nil = refused, never saved.
    func applying(_ edit: LaunchpadEdit) -> LaunchpadLayout? {
        var out = self
        switch edit {
        case .move(let id, let index):
            guard let from = items.firstIndex(where: { $0.itemID == id }) else { return nil }
            let item = out.items.remove(at: from)
            out.items.insert(item, at: index.clamped(to: 0...out.items.count))
        case .makeFolder(let drop, let target, let name):
            guard let name = Self.folderName(name), drop != target, out.topLevelIndex(of: target) != nil, out.contains(drop) else { return nil }
            out.take(drop)
            // Taking the dropped app out may have shifted the target's slot.
            guard let at = out.topLevelIndex(of: target) else { return nil }
            out.items[at] = .folder(Folder(id: UUID(), name: name, apps: [target, drop]))
        case .add(let app, let folder, let position):
            guard out.folderIndex(folder) != nil, out.contains(app), !(out.folder(folder)?.apps.contains(app) ?? true) else { return nil }
            out.take(app)
            guard let f = out.folderIndex(folder) else { return nil }
            out.modifyFolder(at: f) { $0.apps.insert(app, at: (position ?? $0.apps.count).clamped(to: 0...$0.apps.count)) }
        case .remove(let app, let folder):
            guard let f = out.folderIndex(folder), out.folder(folder)?.apps.contains(app) == true else { return nil }
            out.modifyFolder(at: f) { $0.apps.removeAll { $0 == app } }
            out.items.insert(.app(app), at: f + 1)
        case .moveInFolder(let app, let index):
            guard let f = out.items.firstIndex(where: { if case .folder(let x) = $0 { x.apps.contains(app) } else { false } }) else { return nil }
            out.modifyFolder(at: f) {
                $0.apps.removeAll { $0 == app }
                $0.apps.insert(app, at: index.clamped(to: 0...$0.apps.count))
            }
        case .rename(let folder, let name):
            guard let f = out.folderIndex(folder), let trimmed = Self.folderName(name) else { return nil }
            out.modifyFolder(at: f) { $0.name = trimmed }
        case .hide(let app):
            guard out.contains(app) else { return nil }
            out.take(app)
            out.hidden.insert(app)
        case .unhide(let app):
            guard out.hidden.remove(app) != nil else { return nil }
            out.items.append(.app(app))
        case .resetArrangement:
            out.items = []
        }
        return out.normalized()
    }

    /// A name a person typed: trimmed and cut to `maxFolderName`; nil when nothing is left, and the edit is refused.
    private static func folderName(_ name: String) -> String? {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LaunchpadLimits.maxFolderName))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Empty folders go, a folder of one dissolves into its app, each id appears once
    /// (first wins), hidden wins over placed, and a folder id met twice gets a fresh one.
    func normalized() -> LaunchpadLayout {
        var seen = hidden
        var folderIDs: Set<UUID> = []
        var items: [Item] = []
        for item in self.items.prefix(LaunchpadLimits.maxItems) {
            switch item {
            case .app(let id):
                if seen.insert(id).inserted { items.append(item) }
            case .folder(var f):
                f.apps = f.apps.prefix(LaunchpadLimits.maxFolderApps).filter { seen.insert($0).inserted }
                if !folderIDs.insert(f.id).inserted { f.id = UUID(); folderIDs.insert(f.id) }
                if f.apps.count == 1 { items.append(.app(f.apps[0])) } else if !f.apps.isEmpty { items.append(.folder(f)) }
            }
        }
        return LaunchpadLayout(items: items, hidden: hidden)
    }

    // MARK: - Lookups

    private func topLevelIndex(of app: AppID) -> Int? {
        items.firstIndex { if case .app(let id) = $0 { id == app } else { false } }
    }

    private func contains(_ app: AppID) -> Bool {
        items.contains {
            switch $0 {
            case .app(let id): id == app
            case .folder(let f): f.apps.contains(app)
            }
        }
    }

    private func folderIndex(_ id: UUID) -> Int? {
        items.firstIndex { if case .folder(let f) = $0 { f.id == id } else { false } }
    }

    private func folder(_ id: UUID) -> Folder? {
        guard let i = folderIndex(id), case .folder(let f) = items[i] else { return nil }
        return f
    }

    private mutating func modifyFolder(at index: Int, _ change: (inout Folder) -> Void) {
        guard case .folder(var f) = items[index] else { return }
        change(&f)
        items[index] = .folder(f)
    }

    /// Takes an app out of wherever it stands, top level or folder.
    private mutating func take(_ app: AppID) {
        items = items.compactMap {
            switch $0 {
            case .app(let id): return id == app ? nil : $0
            case .folder(var f): f.apps.removeAll { $0 == app }; return .folder(f)
            }
        }
    }
}
