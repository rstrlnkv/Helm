import Foundation
import HelmRuntime

/// One thing Autopilot did to one file, with its names whole (except a scope
/// refusal's), in the module's own store: "moved a file, trashed a file"
/// answers nobody's question. The log keeps names too; only a source outside
/// the allowed folders is logged by rule id instead.
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
    /// Where it was. Not shown, but without it two `report.pdf`s in two
    /// folders, refused by one rule, would collapse into one record.
    /// `PreviewRow` keys the same way. Decodes to `file` when absent.
    public let path: String
    public let kind: Kind
    /// Where it went, what it was renamed to, which tag, or why it was refused.
    /// Empty for the actions that need no second half — a trashed file went to
    /// the Trash and saying so twice is noise.
    public let detail: String
    /// Where the file is now, in full: what "where did that go" opens, since
    /// `detail` is only the parent folder's name. Empty, and nothing offered,
    /// when the module does not know: macOS did not say where the Trash put it,
    /// or a refusal or failure may or may not have left it where it stood.
    public let destination: String

    /// Which pass this belongs to: one value per sweep of a folder or batch of
    /// events. The page groups by it, because "put back the twelve files that
    /// arrived at 14:22" is the gesture people want. Optional like every field
    /// below it: a record stored without one has no group.
    let run: String?
    /// The rule's id, beside the name the row shows: names are not unique, and
    /// the mark a return re-writes is keyed by the id.
    public let ruleID: String?
    /// Who the file at `destination` was when the action ended, so a return
    /// moves the file Helm moved and not whatever stands at that name now. Two
    /// Optional numbers because a plist and a JSON document both hold that shape.
    let device: UInt64?
    let inode: UInt64?
    /// When this action was put back, if it has been. Without it a second press
    /// moves whatever arrived at the named path next.
    public let undoneAt: Date?

    /// The path to reveal, or nothing to offer.
    public var revealPath: String? { destination.isEmpty ? nil : destination }

    /// Whether this row may be offered a return, from the record's shape alone.
    ///
    /// **No stat on purpose**: the page asks this of up to five hundred rows;
    /// whether the file is still there and itself is the undo's business after
    /// the press. A record with nowhere to go back from, no identity or no rule
    /// could only ever refuse.
    public var undoable: Bool {
        undoneAt == nil && !destination.isEmpty && !path.isEmpty
            && device != nil && inode != nil && ruleID != nil
    }

    /// The same record, marked as put back. The row stays — a history that
    /// deleted what it had undone would be a history that hides an action.
    func undone(at when: Date) -> ActionRecord {
        ActionRecord(at: at, rule: rule, file: file, kind: kind, detail: detail,
                     path: path, destination: destination, run: run, ruleID: ruleID,
                     device: device, inode: inode, undoneAt: when)
    }

    public var id: String { "\(at.timeIntervalSince1970)-\(path)-\(kind.rawValue)" }

    /// Whether another record of this kind about this file says the same thing.
    /// An action is worth its own row; a refusal or failure is a *state* that
    /// repeats every sweep.
    var repeatable: Bool { kind == .refused || kind == .failed }

    func isRepeat(of other: ActionRecord) -> Bool {
        kind == other.kind && path == other.path && detail == other.detail
            && rule == other.rule
    }

    init(at: Date, rule: String, file: String, kind: Kind, detail: String,
                path: String = "", destination: String = "", run: String? = nil,
                ruleID: String? = nil, device: UInt64? = nil, inode: UInt64? = nil,
                undoneAt: Date? = nil) {
        self.at = at
        self.rule = rule
        self.file = file
        self.kind = kind
        self.detail = detail
        self.path = path.isEmpty ? file : path
        self.destination = destination
        self.run = run
        self.ruleID = ruleID
        self.device = device
        self.inode = inode
        self.undoneAt = undoneAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decode(Date.self, forKey: .at)
        rule = try c.decode(String.self, forKey: .rule)
        file = try c.decode(String.self, forKey: .file)
        kind = try c.decode(Kind.self, forKey: .kind)
        detail = try c.decode(String.self, forKey: .detail)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? file
        // Missing from older histories, like `path`.
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        // **A stored default would not do this**: the synthesised decoder
        // requires every key, and `JSONDecoder` would abandon the whole document.
        run = try c.decodeIfPresent(String.self, forKey: .run)
        ruleID = try c.decodeIfPresent(String.self, forKey: .ruleID)
        device = try c.decodeIfPresent(UInt64.self, forKey: .device)
        inode = try c.decodeIfPresent(UInt64.self, forKey: .inode)
        undoneAt = try c.decodeIfPresent(Date.self, forKey: .undoneAt)
    }
}

/// What Autopilot did, over the last thirty days.
public enum ActionHistory {

    /// Where the history lives. Here rather than on the engine, because the seal
    /// is written and cleared beside it, and a key spelled twice is renamed once.
    static let storeKey = "history"

    /// Thirty days, because that is the promise the page makes. Anything older
    /// is a file somebody has long since stopped looking for.
    static let window: TimeInterval = 30 * 86_400

    /// A busy Downloads acts hundreds of times a day, and this shares a store
    /// with the rules: unbounded, the history would one day stop the rules saving.
    static let limit = 500

    public struct Summary: Equatable, Sendable {
        var moved = 0, renamed = 0, tagged = 0, trashed = 0
        public var refused = 0, failed = 0
        public var total: Int { moved + renamed + tagged + trashed + refused + failed }
    }

    /// The history with one more thing in it: newest first, nothing older than
    /// the window, nothing beyond the limit.
    static func recording(_ record: ActionRecord,
                                 into history: [ActionRecord],
                                 now: Date = Date()) -> [ActionRecord] {
        // A refusal repeats every sweep, since nothing changed or was stamped:
        // one symlink pointing outside home is 24 rows a day, and the cap would
        // evict the one real move. The newest leads ("it is still failing").
        let deduped = record.repeatable
            ? history.filter { !$0.isRepeat(of: record) }
            : history
        return Array(within([record] + deduped, now: now).prefix(limit))
    }

    /// Everything inside the window, newest first. Applied on the way out too,
    /// so a store written before a clock change puts no stale row on the page.
    static func within(_ history: [ActionRecord], now: Date = Date()) -> [ActionRecord] {
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
    static func decode(_ data: Data?) -> [ActionRecord] {
        guard let data, let history = try? JSONDecoder().decode([ActionRecord].self, from: data)
        else { return [] }
        return history
    }

    static func encode(_ history: [ActionRecord]) -> Data? {
        try? JSONEncoder().encode(history)
    }
}

extension ActionRecord {

    /// What to remember about one plan and its outcome, or nothing: one reading
    /// for the sweep and the watcher alike.
    ///
    /// **Identity is who is at the destination**, for all four actions: that is
    /// where the file ended up. An outcome that left the file where it stood has
    /// no destination and is not asked. `identify` is a seam.
    static func of(_ plan: RulePlan, _ outcome: RuleOutcome, at: Date = Date(),
                   run: String? = nil,
                   identify: (String) -> PathCanonical.FileIdentity? = {
                       PathCanonical.identity(of: $0)
                   }) -> ActionRecord? {
        // **A refusal for scope records neither name nor path**: the history is
        // a plist any process running as the user reads, and such a file is
        // often somewhere macOS protects, reached through a link. The row is the
        // reason and rule only; the repeat collapse keeps it one row.
        if case .refused(.outOfScope) = outcome {
            return ActionRecord(at: at, rule: plan.rule.name, file: "", kind: .refused,
                                detail: RuleOutcome.Refusal.outOfScope.rawValue, path: "",
                                run: run, ruleID: plan.rule.id)
        }
        func make(_ kind: Kind, _ detail: String, _ destination: String) -> ActionRecord {
            let who = destination.isEmpty ? nil : identify(destination)
            return ActionRecord(at: at, rule: plan.rule.name, file: plan.facts.name,
                                kind: kind, detail: detail, path: plan.facts.path,
                                destination: destination, run: run, ruleID: plan.rule.id,
                                device: who?.device, inode: who?.inode)
        }
        switch outcome {
        case let .moved(destination):
            // The folder it landed in, not the whole path, which the page would
            // spell out at length; the whole path is kept beside it to *open* it.
            let folder = URL(fileURLWithPath: destination).deletingLastPathComponent()
                .lastPathComponent
            return make(.moved, folder.isEmpty ? destination : folder, destination)
        case let .renamed(name):
            // The name reported is the one that landed, numbered or not.
            // `FileFacts.path` defaults to empty, and an empty parent would make
            // `/name`, a path at the root of the volume.
            let folder = (plan.facts.path as NSString).deletingLastPathComponent
            return make(.renamed, name, folder.isEmpty ? "" : folder + "/" + name)
        case let .tagged(tag): return make(.tagged, tag, plan.facts.path)
        // Where the Trash put it is not `path` (it renames what it takes when
        // the name is occupied), so the resulting URL is kept: it is where a
        // return puts the file back from. A refusal or a failure has no
        // destination: the file is probably still where it stood.
        case let .trashed(to: bin): return make(.trashed, "", bin)
        case let .refused(reason): return make(.refused, reason.rawValue, "")
        // The file is the person's own and in plain sight, so the row names it.
        // Stored as `.outOfScope`: it reads as the same sentence, and a new word
        // would fall through to a bare verb on an older page.
        case .targetOutOfScope:
            return make(.refused, RuleOutcome.Refusal.outOfScope.rawValue, "")
        case let .failed(description): return make(.failed, description, "")
        // Nothing happened, so there is nothing to say happened. A rule that
        // matches a file it has already dealt with runs on every sweep, and
        // recording that would bury the day's real work under it.
        case .alreadyDone: return nil
        }
    }
}
