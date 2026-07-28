import Foundation

/// One thing Autopilot did to one file.
///
/// The names are here and deliberately not in the log. `HelmLog` carries counts
/// and outcomes and never a file name, which is right for a file that ships to
/// a stranger's machine — but a history that reads "moved a file, moved a file,
/// trashed a file" answers none of the questions somebody actually has. So this
/// lives in the module's own store, on the machine it happened on, and the log
/// keeps saying what it always said.
public struct ActionRecord: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case moved, renamed, tagged, trashed, refused, failed
    }

    public let at: Date
    /// The rule that decided. Rules are named by the person who wrote them, so
    /// this is the one word that says *why* without explaining anything.
    public let rule: String
    /// The file's name, shown as the row's subject.
    public let file: String
    /// Where it was. Not shown — the row reads better without it — but it is
    /// what makes two files one record or two.
    ///
    /// `PreviewRow` was given the same treatment this morning and for the same
    /// reason; this is its sibling and it was missed. Two files called
    /// `report.pdf` in two folders, refused by one rule, collapsed into a
    /// single record and the newer *deleted* the older — worse than the
    /// preview, where the cost was a row not drawn. Optional for decoding: a
    /// history written before today has no such key.
    public let path: String
    public let kind: Kind
    /// Where it went, what it was renamed to, which tag, or why it was refused.
    /// Empty for the actions that need no second half — a trashed file went to
    /// the Trash and saying so twice is noise.
    public let detail: String

    public var id: String { "\(at.timeIntervalSince1970)-\(path)-\(kind.rawValue)" }

    /// Whether another record of this kind about this file says the same thing.
    ///
    /// An action happened once and each one is worth its own row. A refusal or
    /// a failure is a *state* — the same file, the same reason, every sweep —
    /// and a hundred rows of it say no more than one does.
    public var repeatable: Bool { kind == .refused || kind == .failed }

    public func isRepeat(of other: ActionRecord) -> Bool {
        kind == other.kind && path == other.path && detail == other.detail
            && rule == other.rule
    }

    public init(at: Date, rule: String, file: String, kind: Kind, detail: String,
                path: String = "") {
        self.at = at
        self.rule = rule
        self.file = file
        self.kind = kind
        self.detail = detail
        self.path = path.isEmpty ? file : path
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decode(Date.self, forKey: .at)
        rule = try c.decode(String.self, forKey: .rule)
        file = try c.decode(String.self, forKey: .file)
        kind = try c.decode(Kind.self, forKey: .kind)
        detail = try c.decode(String.self, forKey: .detail)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? file
    }
}

/// What Autopilot did, over the last thirty days.
public enum ActionHistory {

    /// Thirty days, because that is the promise the page makes. Anything older
    /// is a file somebody has long since stopped looking for.
    public static let window: TimeInterval = 30 * 86_400

    /// A busy Downloads folder acts hundreds of times a day, and this shares a
    /// store with the rules. Unbounded, the history would eventually be the
    /// reason the rules stop saving — which would be Autopilot breaking itself
    /// by keeping too good a record.
    public static let limit = 500

    public struct Summary: Equatable, Sendable {
        public var moved = 0, renamed = 0, tagged = 0, trashed = 0
        public var refused = 0, failed = 0
        public var total: Int { moved + renamed + tagged + trashed + refused + failed }
    }

    /// The history with one more thing in it: newest first, nothing older than
    /// the window, nothing beyond the limit.
    public static func recording(_ record: ActionRecord,
                                 into history: [ActionRecord],
                                 now: Date = Date()) -> [ActionRecord] {
        // A refusal repeats. Nothing about the file changed, nothing is
        // stamped, so the next sweep decides the same thing about it an hour
        // later — one symlink pointing outside home is 24 identical rows a day,
        // 720 in the window, and the cap then evicts the one move that actually
        // happened. `.alreadyDone` is already dropped for this reason; a
        // refusal is the same event wearing a different name.
        //
        // The newest of a repeat is what a person wants ("it is still failing"),
        // so the old one goes and the new one leads.
        let deduped = record.repeatable
            ? history.filter { !$0.isRepeat(of: record) }
            : history
        return Array(within([record] + deduped, now: now).prefix(limit))
    }

    /// Everything inside the window, newest first.
    ///
    /// Applied on the way out as well as on the way in: a store written before
    /// a clock change, or by a build that pruned differently, must not put a
    /// stale row on the page.
    public static func within(_ history: [ActionRecord], now: Date = Date()) -> [ActionRecord] {
        let oldest = now.addingTimeInterval(-window)
        return history
            .filter { $0.at >= oldest }
            .sorted { $0.at > $1.at }
    }

    public static func summary(of history: [ActionRecord], now: Date = Date()) -> Summary {
        var summary = Summary()
        for record in within(history, now: now) {
            switch record.kind {
            case .moved: summary.moved += 1
            case .renamed: summary.renamed += 1
            case .tagged: summary.tagged += 1
            case .trashed: summary.trashed += 1
            case .refused: summary.refused += 1
            case .failed: summary.failed += 1
            }
        }
        return summary
    }

    /// The store outlives the build that wrote it, so a record this build
    /// cannot read costs the reader a shorter history and nothing worse.
    public static func decode(_ data: Data?) -> [ActionRecord] {
        guard let data, let history = try? JSONDecoder().decode([ActionRecord].self, from: data)
        else { return [] }
        return history
    }

    public static func encode(_ history: [ActionRecord]) -> Data? {
        try? JSONEncoder().encode(history)
    }
}

public extension ActionRecord {

    /// What to remember about one plan and how it turned out, or nothing.
    ///
    /// Both the sweep and the watcher take the same six outcomes apart, and
    /// they used to do it twice — the watcher's copy logged nothing at all for
    /// a successful action until that was fixed. One reading of an outcome
    /// means the record cannot say one thing on the timer and another when a
    /// file arrives.
    static func of(_ plan: RulePlan, _ outcome: RuleOutcome, at: Date = Date()) -> ActionRecord? {
        let make: (Kind, String) -> ActionRecord = { kind, detail in
            ActionRecord(at: at, rule: plan.rule.name, file: plan.facts.name,
                         kind: kind, detail: detail, path: plan.facts.path)
        }
        switch outcome {
        case let .moved(destination):
            // The folder it landed in, not the whole path: the page is a
            // report, and "→ /Users/r/Documents/Invoices/march.pdf" is the
            // file's new name spelled out at length.
            let folder = URL(fileURLWithPath: destination).deletingLastPathComponent()
                .lastPathComponent
            return make(.moved, folder.isEmpty ? destination : folder)
        case let .renamed(name): return make(.renamed, name)
        case let .tagged(tag): return make(.tagged, tag)
        case .trashed: return make(.trashed, "")
        case let .refused(reason): return make(.refused, reason.rawValue)
        case let .failed(description): return make(.failed, description)
        // Nothing happened, so there is nothing to say happened. A rule that
        // matches a file it has already dealt with runs on every sweep, and
        // recording that would bury the day's real work under it.
        case .alreadyDone: return nil
        }
    }
}
