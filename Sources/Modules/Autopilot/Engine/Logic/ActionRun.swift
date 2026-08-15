import Foundation

/// One pass of Autopilot's, as the page reads it: everything one sweep or one
/// batch of filesystem events did, and what a header may say about it.
///
/// Five hundred rows is not something anybody can act on; "twelve files arrived
/// in Downloads at 14:22" is. Everything here comes out of the records
/// themselves — a header naming a folder the pass did not come from would be a
/// claim about somebody's Mac that nothing checked.
public struct ActionRun: Identifiable, Equatable, Sendable {
    /// The pass's own id, or the single record's when it belongs to no pass.
    public let id: String
    /// When the pass happened, which for a reader is its newest action.
    public let at: Date
    /// The one folder these came from, by name, or nothing when they came from
    /// several. A watched folder with subfolders makes passes that touch three
    /// of them at once.
    public let folder: String?
    /// Every record in the pass, in the order the page draws them — including
    /// the ones that cannot be put back, because the pass is a record of what
    /// happened before it is a thing to undo.
    public let records: [ActionRecord]

    public init(id: String, at: Date, folder: String?, records: [ActionRecord]) {
        self.id = id
        self.at = at
        self.folder = folder
        self.records = records
    }

    /// The records a return could act on. The count on a button is a promise,
    /// so a pass of twelve where nine are undoable offers nine.
    public var undoable: [ActionRecord] { records.filter(\.undoable) }

    /// Whether the pass may be put back as a whole. A record that belongs to no
    /// pass is never offered one: it stands alone, and its own row is the
    /// gesture.
    public var canBePutBack: Bool { records.count > 1 && !undoable.isEmpty }
}

public extension ActionHistory {

    /// The history in passes, newest first.
    ///
    /// Records with no pass of their own each stand alone rather than
    /// collapsing into one enormous group — a history written before this build
    /// has none, and one press over all of it is not a gesture anybody meant.
    static func runs(of history: [ActionRecord], now: Date = Date()) -> [ActionRun] {
        var order: [String] = []
        var grouped: [String: [ActionRecord]] = [:]
        for record in within(history, now: now) {
            let key = record.run ?? record.id
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(record)
        }
        return order.compactMap { key in
            guard let records = grouped[key], let newest = records.first?.at else { return nil }
            return ActionRun(id: key, at: newest, folder: oneFolder(of: records),
                             records: records)
        }
    }

    /// The folder every one of these came from, by name, or nothing.
    private static func oneFolder(of records: [ActionRecord]) -> String? {
        let folders = Set(records.map { ($0.path as NSString).deletingLastPathComponent })
        guard folders.count == 1, let only = folders.first, !only.isEmpty else { return nil }
        let name = (only as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }
}
