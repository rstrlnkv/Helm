import Foundation
import HelmRuntime

/// Everything a return asks of the disk.
///
/// A port for the reason `RuleRunner`'s `ancestry` is a seam and for one more:
/// the states this has to tell apart are states a test cannot conjure on the
/// machine running the suite. A volume that will not keep an extended
/// attribute, a directory swapped for a symlink between two syscalls, a Trash
/// emptied mid-decision — each is a branch that decides whether somebody's file
/// moves, and each is unreachable from a temporary folder.
protocol UndoFiles: Sendable {
    /// Who is at `path`, by `lstat`, or nothing when there is nothing.
    func identity(of path: String) -> PathCanonical.FileIdentity?
    /// Where `path`'s resolved parent chain leads *now*.
    func ancestry(of path: String) -> PathCanonical.AncestryIdentity?
    func directoryExists(_ path: String) -> Bool
    func move(_ from: String, to: String) throws
    func tags(of path: String) throws -> [String]
    func setTags(_ tags: [String], on path: String) throws
    /// Whether the mark stuck.
    func stamp(_ path: String, rule: String, key: Data) -> Bool
}

struct SystemUndoFiles: UndoFiles {
    func identity(of path: String) -> PathCanonical.FileIdentity? {
        PathCanonical.identity(of: path)
    }

    func ancestry(of path: String) -> PathCanonical.AncestryIdentity? {
        PathCanonical.ancestryIdentity(of: path)
    }

    func directoryExists(_ path: String) -> Bool {
        var directory: ObjCBool = false
        let there = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
        return there && directory.boolValue
    }

    func move(_ from: String, to: String) throws {
        try FileManager.default.moveItem(atPath: from, toPath: to)
    }

    func tags(of path: String) throws -> [String] {
        try URL(fileURLWithPath: path).resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
    }

    func setTags(_ tags: [String], on path: String) throws {
        var values = URLResourceValues()
        values.tagNames = tags
        var url = URL(fileURLWithPath: path)
        try url.setResourceValues(values)
    }

    func stamp(_ path: String, rule: String, key: Data) -> Bool {
        RuleStamp(key: key).stamp(path, by: rule)
    }
}

/// One record, put back.
///
/// **A record is a claim, not an instruction.** The history lives in the same
/// plist the rules do — writable by any process running as this user — so a
/// forged record is a ready-made way to make Helm move a file with Helm's Full
/// Disk Access: `{moved, destination: "~/Library/Messages/chat.db", path:
/// "~/Downloads/x"}` reads perfectly on the page and would carry protected
/// content out to where the forger can read it. Every field is therefore
/// checked before anything moves, in the same order `RuleRunner.run` checks
/// its own:
///
/// 1. the record has been put back already, or never had anything to put back;
/// 2. **`WatchScope` on both ends** — `~/Library` refused whole, `~/.Trash`
///    allowed, since the source end of a return out of the Trash is not a
///    place a rule reaches but is exactly where the file is;
/// 3. **identity** — the thing at that path is the thing Helm acted on;
/// 4. **where both ends lead**, read at the check and again beside the move.
///
/// `UserFileScope` is not asked, and that is not an omission: it answers "may
/// this be trashed without breaking the machine", and a return deletes nothing.
struct UndoRunner: Sendable {
    /// Which home `WatchScope` measures against, injected for the reason
    /// `RuleRunner` takes one: a test gives the gate a different home rather
    /// than an exemption from it.
    private let home: String
    private let files: UndoFiles

    init(home: String = NSHomeDirectory(), files: UndoFiles = SystemUndoFiles()) {
        self.home = home
        self.files = files
    }

    /// `key` is the seal key, and nil is a keychain that would not answer. The
    /// file still goes back — refusing a person their file because a mark
    /// cannot be written is the wrong end to fail at — and the outcome says it
    /// went back unmarked.
    func undo(_ record: ActionRecord, key: Data?) -> UndoOutcome {
        guard record.undoneAt == nil else { return .refused(.alreadyUndone) }
        // Everything a return needs the record to have said. A refusal, a
        // failure and every record written before this build land here: they
        // moved nothing, so there is nothing to identify and nowhere to go.
        guard let ruleID = record.ruleID, let device = record.device, let inode = record.inode,
              !record.destination.isEmpty, !record.path.isEmpty
        else { return .refused(.noIdentity) }
        // Both ends, before anything is read off the disk.
        guard WatchScope.allows(record.destination, home: home),
              WatchScope.allows(record.path, home: home)
        else { return .refused(.originOutOfScope) }

        guard let who = files.identity(of: record.destination) else {
            // The Trash says it differently: "the file is not in the Trash any
            // more" covers emptying it and taking the file out by hand alike,
            // and both are things the person did rather than things that broke.
            return .refused(record.kind == .trashed ? .trashEmptied : .notThere)
        }
        guard who == PathCanonical.FileIdentity(device: device, inode: inode) else {
            return .refused(.notTheSameFile)
        }

        switch record.kind {
        case .moved, .renamed, .trashed:
            return putBack(record, ruleID: ruleID, key: key)
        case .tagged:
            return untag(record, ruleID: ruleID, key: key)
        case .refused, .failed:
            // Unreachable: neither carries a destination, so both were refused
            // above. Exhaustive rather than defaulted, so a seventh kind is a
            // build error here instead of a record that quietly cannot be
            // undone.
            return .refused(.noIdentity)
        }
    }

    private func putBack(_ record: ActionRecord, ruleID: String, key: Data?) -> UndoOutcome {
        let origin = (record.path as NSString).deletingLastPathComponent
        guard files.directoryExists(origin) else { return .refused(.originGone) }

        // Taken before the collision loop, which is the window this pair
        // narrows — the same shape `RuleRunner.move` uses, and for the same
        // measured reason.
        let approvedSource = files.ancestry(of: record.destination)
        let approvedOrigin = files.ancestry(of: record.path)

        let target: String
        if files.identity(of: record.path) == nil {
            target = record.path
        } else if record.kind == .renamed {
            return .refused(.nameTaken)
        } else {
            target = free(record.path)
        }

        guard files.ancestry(of: record.destination) == approvedSource,
              files.ancestry(of: target) == approvedOrigin
        else { return .refused(.changedSinceCheck) }
        do {
            try files.move(record.destination, to: target)
        } catch {
            return .failed(HelmFailure.describe(error))
        }
        return .restored(to: target, stamped: mark(target, ruleID, key))
    }

    /// The tag from the record and no other. The identity check above is what
    /// makes writing here safe: a path that had become a symlink since the rule
    /// ran would be a different object, and `lstat` would have said so.
    private func untag(_ record: ActionRecord, ruleID: String, key: Data?) -> UndoOutcome {
        do {
            var tags = try files.tags(of: record.destination)
            guard tags.contains(record.detail) else { return .refused(.alreadyUndone) }
            tags.removeAll { $0 == record.detail }
            try files.setTags(tags, on: record.destination)
        } catch {
            return .failed(HelmFailure.describe(error))
        }
        return .restored(to: record.destination, stamped: mark(record.destination, ruleID, key))
    }

    /// **The return marks the file for the rule that acted; it never unmarks
    /// it.** A file out of the Trash comes back clean, and the rule that binned
    /// it would bin it again within the hour — the ping-pong this feature would
    /// otherwise build. A move within a volume kept its mark and this writes
    /// the same value again, which is why one line covers all four actions
    /// without branching on any of them.
    private func mark(_ path: String, _ ruleID: String, _ key: Data?) -> Bool {
        guard let key else { return false }
        return files.stamp(path, rule: ruleID, key: key)
    }

    /// The old name, or a numbered one beside it when something else has taken
    /// it since. `RuleRunner` numbers an arrival the same way, out of the same
    /// helper — the Finder's `a 2.pdf`.
    private func free(_ path: String) -> String {
        FreeName.beside(URL(fileURLWithPath: path)) { files.identity(of: $0) != nil }.path
    }
}
