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
        /// The next item begins a new page, whatever the page before holds. A marker in the list, not a property of an
        /// item, so the pages stay when the item after it is moved away; `normalized()` keeps one only between two items.
        case pageBreak
    }

    public internal(set) var items: [Item] = []
    public internal(set) var hidden: Set<AppID> = []

    static let empty = LaunchpadLayout()
}

/// One gesture, one case. A vanished id is refused (`applying` returns nil). A drop names its place by an **anchor id**,
/// never by an index: the window shows a subset of `items` (hidden and missing entries are not drawn), so a displayed
/// index is not the layout's.
public enum LaunchpadEdit: Equatable, Sendable {
    /// Top-level reorder; the index is clamped.
    case move(String, toIndex: Int)
    /// The folder takes the target's slot, apps `[target, dropped]`; the name is passed in, the engine holds no strings.
    case makeFolder(drop: AppID, onto: AppID, name: String)
    /// Next to a member of the folder (`relativeTo`), or last when it is nil. A member of it is refused (`moveInFolder`), as is a full folder.
    case add(AppID, toFolder: UUID, relativeTo: AppID?, after: Bool)
    /// An app, or a folder by its UUID string, from wherever it stands (top level or a folder) to the top level beside
    /// the top-level item `relativeTo`.
    case place(String, relativeTo: String, after: Bool)
    /// An app, or a folder by its UUID string, to the end, on a page of its own.
    case newPage(moving: String)
    /// Lands right after the folder.
    case remove(AppID, fromFolder: UUID)
    case moveInFolder(AppID, toIndex: Int)
    case rename(UUID, to: String)
    case hide(AppID)
    case unhide(AppID)
    /// Order and folders go; hidden stays. The engine reconciles the result, which puts every shown app back in catalog order.
    case resetArrangement
}

/// Where a dragged item was lifted from: the top level, or the open folder with this id.
public enum LaunchpadDropSource: Equatable, Sendable {
    case top
    case folder(UUID)
}

/// Where it was let go, by anchors (ids), not by tiles on the screen.
public enum LaunchpadDropDestination: Equatable, Sendable {
    /// In the gap before or after a top-level item.
    case beside(String, after: Bool)
    /// On the middle of a top-level item.
    case onto(String)
    /// In the open folder, next to a member (nil: last).
    case intoFolder(UUID, relativeTo: AppID?, after: Bool)
    /// After the last page, on a page of its own.
    case newPage
}

extension LaunchpadLayout.Item {
    /// An app's id, or a folder's UUID string; a page break has none and is "".
    public var itemID: String {
        switch self {
        case .app(let id): id
        case .folder(let f): f.id.uuidString
        case .pageBreak: ""
        }
    }
}

extension LaunchpadLayout {

    /// What letting go of `id` (an app, or a folder's UUID string) means, or nil when it means nothing: an id that is not
    /// where `source` says, an anchor that is not there, a drop that leaves the layout as it is. An app dropped on an app
    /// makes a folder named `folderName`, on a folder joins it; **a folder never nests**, dropped on anything it only
    /// takes that item's place, and it is refused inside a folder.
    public func edit(dropping id: String, source: LaunchpadDropSource, destination: LaunchpadDropDestination,
                     folderName: String) -> LaunchpadEdit? {
        switch source {
        case .top: guard itemIndex(id) != nil else { return nil }
        case .folder(let f): guard folder(f)?.apps.contains(id) == true else { return nil }
        }
        // An id that is an app's is the app's, whatever a folder's identity is spelled like (`takeItem` looks the app up first too).
        let draggedFolder = !contains(id) && items.contains { if case .folder(let f) = $0 { f.id.uuidString == id } else { false } }
        let edit: LaunchpadEdit
        switch destination {
        case .beside(let anchor, let after):
            edit = .place(id, relativeTo: anchor, after: after)
        case .newPage:
            edit = .newPage(moving: id)
        case .onto(let target):
            guard target != id, let t = itemIndex(target) else { return nil }
            if draggedFolder, let from = itemIndex(id) {
                edit = .place(id, relativeTo: target, after: from < t)
            } else if case .folder(let f) = items[t] {
                edit = .add(id, toFolder: f.id, relativeTo: nil, after: true)
            } else {
                edit = .makeFolder(drop: id, onto: target, name: folderName)
            }
        case .intoFolder(let folderID, let anchor, let after):
            guard !draggedFolder, let members = folder(folderID)?.apps else { return nil }
            guard let from = members.firstIndex(of: id) else {
                edit = .add(id, toFolder: folderID, relativeTo: anchor, after: after)
                break
            }
            var rest = members
            rest.remove(at: from)
            var at = rest.count
            if let anchor {
                guard let i = rest.firstIndex(of: anchor) else { return nil }
                at = after ? i + 1 : i
            }
            edit = .moveInFolder(id, toIndex: at)
        }
        guard let result = applying(edit), result != normalized() else { return nil }
        return edit
    }

    /// nil = refused, never saved.
    func applying(_ edit: LaunchpadEdit) -> LaunchpadLayout? {
        var out = self
        switch edit {
        case .move(let id, let index):
            guard let from = itemIndex(id) else { return nil }
            let item = out.items.remove(at: from)
            out.items.insert(item, at: index.clamped(to: 0...out.items.count))
        case .makeFolder(let drop, let target, let name):
            guard let name = Self.folderName(name), drop != target, out.topLevelIndex(of: target) != nil, out.contains(drop) else { return nil }
            out.take(drop)
            // Taking the dropped app out may have shifted the target's slot.
            guard let at = out.topLevelIndex(of: target) else { return nil }
            out.items[at] = .folder(Folder(id: UUID(), name: name, apps: [target, drop]))
        case .add(let app, let folder, let anchor, let after):
            guard let members = out.folder(folder)?.apps, out.contains(app), !members.contains(app),
                  members.count < LaunchpadLimits.maxFolderApps, anchor.map(members.contains) ?? true else { return nil }
            out.take(app)
            guard let f = out.folderIndex(folder) else { return nil }
            out.modifyFolder(at: f) {
                let next = anchor.flatMap($0.apps.firstIndex(of:)).map { after ? $0 + 1 : $0 }
                $0.apps.insert(app, at: next ?? $0.apps.count)
            }
        case .place(let id, let anchor, let after):
            guard id != anchor, out.itemIndex(anchor) != nil, let item = out.takeItem(id), let at = out.itemIndex(anchor) else { return nil }
            out.items.insert(item, at: after ? at + 1 : at)
        case .newPage(let id):
            guard let item = out.takeItem(id) else { return nil }
            out.items += [.pageBreak, item]
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
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Empty folders go, a folder of one dissolves into its app, each id appears once
    /// (first wins), hidden wins over placed, a folder id met twice gets a fresh one, and a page break
    /// stands only between two items (no first, no last, no two in a row: no empty page), at most `LaunchpadLimits.maxPages - 1` of them.
    func normalized() -> LaunchpadLayout {
        var seen = hidden
        var folderIDs: Set<UUID> = []
        var items: [Item] = []
        var breaks = 0
        for item in self.items.prefix(LaunchpadLimits.maxItems) {
            switch item {
            case .pageBreak:
                if let last = items.last, last != .pageBreak, breaks < LaunchpadLimits.maxPages - 1 { items.append(item); breaks += 1 }
            case .app(let id):
                if seen.insert(id).inserted { items.append(item) }
            case .folder(var f):
                f.apps = f.apps.prefix(LaunchpadLimits.maxFolderApps).filter { seen.insert($0).inserted }
                if !folderIDs.insert(f.id).inserted { f.id = UUID(); folderIDs.insert(f.id) }
                if f.apps.count == 1 { items.append(.app(f.apps[0])) } else if !f.apps.isEmpty { items.append(.folder(f)) }
            }
        }
        if items.last == .pageBreak { items.removeLast() }
        return LaunchpadLayout(items: items, hidden: hidden)
    }

    // MARK: - Lookups

    /// An app's, or a folder's (UUID string), place at the top level; a page break is nobody's.
    private func itemIndex(_ id: String) -> Int? {
        items.firstIndex { $0 != .pageBreak && $0.itemID == id }
    }

    private func topLevelIndex(of app: AppID) -> Int? {
        items.firstIndex { if case .app(let id) = $0 { id == app } else { false } }
    }

    private func contains(_ app: AppID) -> Bool {
        items.contains {
            switch $0 {
            case .app(let id): id == app
            case .folder(let f): f.apps.contains(app)
            case .pageBreak: false
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
            case .pageBreak: return $0
            }
        }
    }

    /// Takes an app, or else a top-level folder by its UUID string, out of where it stands; nil when there is none. An app
    /// first: a bundle id is whatever a bundle says, and may be spelled as a folder's identity.
    private mutating func takeItem(_ id: String) -> Item? {
        if contains(id) {
            take(id)
            return .app(id)
        }
        guard let i = items.firstIndex(where: { if case .folder(let f) = $0 { f.id.uuidString == id } else { false } }) else { return nil }
        return items.remove(at: i)
    }
}
