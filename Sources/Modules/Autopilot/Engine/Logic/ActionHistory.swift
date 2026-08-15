import Foundation
import HelmRuntime

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
    /// Where the file is now, in full.
    ///
    /// This section's whole job is "where did that go", and neither of the other
    /// two fields could answer it: `detail` is the destination's parent folder
    /// *name*, which reads well and opens nothing, and `path` is where the file
    /// was — after a move, a path nothing is at.
    ///
    /// Empty when the module does not know where the file ended up: the Trash
    /// renames what it takes and was never asked for the resulting URL, and a
    /// refusal or a failure may or may not have left the file where it stood.
    /// An offer that silently does nothing is worse than no offer.
    public let destination: String

    /// Which pass this record belongs to — one value for a whole sweep of one
    /// folder, and one for a whole batch of filesystem events.
    ///
    /// The page groups by it, because "put back the twelve files that arrived
    /// at 14:22" is the gesture somebody actually wants and "put back every
    /// file this rule ever moved" is one nobody should be offered. Optional
    /// like every field below it: a history written before this build has no
    /// such key, and those records simply have no group.
    public let run: String?
    /// The rule's id, beside the name the row shows.
    ///
    /// Names are not unique — two rules in one folder may be called the same
    /// thing — and the mark a return re-writes is keyed by the id. Without it a
    /// return could stamp the file for the wrong rule, which is the same as not
    /// stamping it at all.
    public let ruleID: String?
    /// Who the file at `destination` was when the action ended.
    ///
    /// The reason a return moves the file Helm moved rather than whatever is
    /// sitting at that path now — a name is a place, and something else can be
    /// standing in it an hour later. Two halves rather than one struct because
    /// this is stored data, and two Optional numbers is the shape a plist and a
    /// JSON document both already hold.
    public let device: UInt64?
    public let inode: UInt64?
    /// When this action was put back, if it has been.
    ///
    /// Without it the second press moves a different file: the row still says
    /// "moved to Invoices", the file is no longer there, and the path it names
    /// now holds whatever arrived next.
    public let undoneAt: Date?

    /// The path to reveal, or nothing to offer.
    public var revealPath: String? { destination.isEmpty ? nil : destination }

    /// Whether this row may be offered a return, decided from the record's own
    /// shape and nothing else.
    ///
    /// **No stat here on purpose.** The page draws up to five hundred of these
    /// and the verdict is asked for once per row; whether the file is still
    /// there, still itself and still somewhere a rule may reach is the undo's
    /// own business, answered after the press. What this settles is the shape:
    /// a record with nowhere to go back from, no identity to check it against
    /// or no rule to re-mark it for could only ever refuse.
    public var undoable: Bool {
        undoneAt == nil && !destination.isEmpty && !path.isEmpty
            && device != nil && inode != nil && ruleID != nil
    }

    /// The same record, marked as put back. The row stays — a history that
    /// deleted what it had undone would be a history that hides an action.
    public func undone(at when: Date) -> ActionRecord {
        ActionRecord(at: at, rule: rule, file: file, kind: kind, detail: detail,
                     path: path, destination: destination, run: run, ruleID: ruleID,
                     device: device, inode: inode, undoneAt: when)
    }

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
        // Missing in every history written before this build, the same way
        // `path` is missing from the ones written before that.
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        // **A stored default would not have done this.** The synthesised
        // decoder requires the key whatever a property's initial value is, and
        // `JSONDecoder` then abandons the whole document rather than the one
        // field — so a history written by yesterday's build would decode to
        // nothing at all, which is the section going blank on upgrade.
        run = try c.decodeIfPresent(String.self, forKey: .run)
        ruleID = try c.decodeIfPresent(String.self, forKey: .ruleID)
        device = try c.decodeIfPresent(UInt64.self, forKey: .device)
        inode = try c.decodeIfPresent(UInt64.self, forKey: .inode)
        undoneAt = try c.decodeIfPresent(Date.self, forKey: .undoneAt)
    }
}

/// What Autopilot did, over the last thirty days.
public enum ActionHistory {

    /// Where the history lives in the module's own namespace.
    ///
    /// Here rather than on the engine, because the engine is not the only
    /// reader any more: the seal is written and thrown away beside the payload,
    /// and a key spelled in two places is one that only one of them renames.
    public static let storeKey = "history"

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
    ///
    /// `identify` is a seam with the real reading behind it. **Identity is who
    /// is at the destination**, one rule for all four actions and no branching:
    /// the destination is where the file ended up, so "is this still the file
    /// Helm acted on" has one form — and an outcome that left the file where it
    /// stood has no destination, so it is not asked at all.
    static func of(_ plan: RulePlan, _ outcome: RuleOutcome, at: Date = Date(),
                   run: String? = nil,
                   identify: (String) -> PathCanonical.FileIdentity? = {
                       PathCanonical.identity(of: $0)
                   }) -> ActionRecord? {
        func make(_ kind: Kind, _ detail: String, _ destination: String) -> ActionRecord {
            let who = destination.isEmpty ? nil : identify(destination)
            return ActionRecord(at: at, rule: plan.rule.name, file: plan.facts.name,
                                kind: kind, detail: detail, path: plan.facts.path,
                                destination: destination, run: run, ruleID: plan.rule.id,
                                device: who?.device, inode: who?.inode)
        }
        switch outcome {
        case let .moved(destination):
            // The folder it landed in, not the whole path: the page is a
            // report, and "→ /Users/r/Documents/Invoices/march.pdf" is the
            // file's new name spelled out at length. The whole path is kept
            // beside it, because the row also has to be able to *open* it.
            let folder = URL(fileURLWithPath: destination).deletingLastPathComponent()
                .lastPathComponent
            return make(.moved, folder.isEmpty ? destination : folder, destination)
        case let .renamed(name):
            // A rename never leaves the folder, and the name reported is the
            // one that landed — including the numbered form a collision makes.
            // `FileFacts.path` defaults to empty, and an empty parent would
            // make `/name`: a path at the root of the volume, which is not
            // where the file is and may well be something else.
            let folder = (plan.facts.path as NSString).deletingLastPathComponent
            return make(.renamed, name, folder.isEmpty ? "" : folder + "/" + name)
        case let .tagged(tag): return make(.tagged, tag, plan.facts.path)
        // Where the Trash put it is not `path` — it renames what it takes when
        // the name is occupied — so the resulting URL is asked for and kept.
        // The most dangerous thing the module does was the one action with
        // nowhere to put the file back to. A refusal or a failure still has no
        // destination: the file is probably still where it stood, and probably
        // is not something to open a window on.
        case let .trashed(to: bin): return make(.trashed, "", bin)
        case let .refused(reason): return make(.refused, reason.rawValue, "")
        case let .failed(description): return make(.failed, description, "")
        // Nothing happened, so there is nothing to say happened. A rule that
        // matches a file it has already dealt with runs on every sweep, and
        // recording that would bury the day's real work under it.
        case .alreadyDone: return nil
        }
    }
}
