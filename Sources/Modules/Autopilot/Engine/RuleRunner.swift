import Foundation
import HelmRuntime

/// What happened to one file. Reported rather than assumed: a rule that ran on
/// a hundred files and could not touch three has to be able to say which three.
public enum RuleOutcome: Equatable, Sendable {
    case moved(to: String)
    case renamed(to: String)
    case tagged(String)
    case trashed
    /// The rule had already had its turn at this file.
    case alreadyDone
    case refused(Refusal)
    case failed(String)

    // CaseIterable so the guard on how these read on screen loops the real
    // list instead of keeping a copy — see `ARefusalSpeaksTheLanguageTests`.
    public enum Refusal: String, CaseIterable, Equatable, Sendable {
        /// The file or the destination is not the user's to move.
        case outOfScope
        /// A rename pattern the filesystem should not be asked to take.
        case badPattern
        case missing
        /// Where the path leads changed between the gate and the act — a
        /// symlinked ancestor was swapped in the window, so the gate approved
        /// one place and the move would have taken another.
        case changedSinceCheck
    }
}

/// The plan, performed. One file at a time, and every path through it either
/// does exactly one thing or does nothing and says why.
struct RuleRunner: Sendable {
    /// Which home `WatchScope` measures against. Injected so a test can put its
    /// fixtures somewhere real without writing into the person's own folders —
    /// the gate is the same gate, asked about a different home.
    private let home: String
    /// Where a path leads, read at the gate and again at the act. A seam because
    /// the window between those two readings cannot be raced reliably in a test
    /// — see `TheActTakesWhatTheGateApprovedTests`, which answers
    /// the first reading from the real filesystem and swaps the disk underneath
    /// the second.
    private let ancestry: @Sendable (String) -> PathCanonical.AncestryIdentity?

    init(home: String = NSHomeDirectory(),
         ancestry: @escaping @Sendable (String) -> PathCanonical.AncestryIdentity? = {
             PathCanonical.ancestryIdentity(of: $0)
         }) {
        self.home = home
        self.ancestry = ancestry
    }

    /// `key` is the seal key, which is what makes a stamp Helm's own rather than
    /// anybody's — see `StampMark`. Nil is a key that could not be read, and it
    /// means the marks on a file cannot be checked or written: the plan is
    /// carried out and the rule gets another turn at the same file next sweep,
    /// which is what an unstampable volume already looks like. Unreachable from
    /// the module's own triggers, which have no rules to run without a key.
    func run(_ plan: RulePlan, at path: String, key: Data?) -> RuleOutcome {
        guard FileManager.default.fileExists(atPath: path) else { return .refused(.missing) }
        let stamp = key.map(RuleStamp.init(key:))
        // Asked before anything happens, so a file already handled by this rule
        // costs a stat rather than a move.
        guard stamp?.isStamped(path, by: plan.rule.id) != true else { return .alreadyDone }
        // The file itself has to be somewhere a rule may reach, whatever the
        // rule says — the rules are JSON in a plist any process can write, so
        // this is the only place the question is settled. `WatchScope` rather
        // than `UserFileScope`: the shared gate answers "may this be trashed
        // without breaking the machine", which says yes to `~/Library/Messages`
        // and to `~/Library/LaunchAgents`.
        guard WatchScope.allows(path, home: home) else { return .refused(.outOfScope) }
        let approved = ancestry(path)

        let outcome = perform(plan, at: path, approved: approved)
        switch outcome {
        case .refused, .failed, .alreadyDone:
            break
        case let .moved(to: destination):
            // Stamped where it landed: the mark travels with a move, but the
            // path we know is the old one.
            note(destination, plan, stamp)
        case let .renamed(to: name):
            note((path as NSString).deletingLastPathComponent + "/" + name, plan, stamp)
        case .tagged:
            note(path, plan, stamp)
        case .trashed:
            // Nothing to stamp: the file is in the Trash, and stamping the path
            // it used to have logged a warning naming a file on every single
            // successful deletion.
            break
        }
        return outcome
    }

    /// A stamp that will not stick is logged and shrugged off. Refusing the
    /// file instead would make a volume without extended attributes a volume
    /// where no rule works; acting anyway and not recording it is how a rule
    /// loops. Between those, the loop is the one the sweep can survive: it
    /// re-runs an idempotent action on an unchanged file.
    private func note(_ path: String, _ plan: RulePlan, _ stamp: RuleStamp?) {
        guard stamp?.stamp(path, by: plan.rule.id) != true else { return }
        HelmLog.shared.warn("autopilot", "could not stamp \(Redact.path(path))")
    }

    private func perform(_ plan: RulePlan, at path: String,
                         approved: PathCanonical.AncestryIdentity?) -> RuleOutcome {
        let url = URL(fileURLWithPath: path)
        switch plan.action {
        case let .move(to: destination):
            return move(url, into: URL(fileURLWithPath: destination), approved: approved)

        case let .sortIntoSubfolder(scheme):
            let bucket = SortBucket.name(for: plan.facts, scheme: scheme)
            let here = url.deletingLastPathComponent()
            // A file already in its bucket has arrived. The bucket used to be
            // hung off the parent unconditionally, so `Images/a.jpg` was
            // offered `Images/Images/`, and the only thing standing between
            // that and a file buried a level deeper every hour was the stamp
            // — which `note` explicitly tolerates the loss of, on any volume
            // that will not keep an extended attribute or whose AppleDouble
            // sidecar something drops (ARCHITECTURE.md § Autopilot; exFAT,
            // which used to be named here, keeps it).
            //
            // Compared without case, because `images` and `Images` are one
            // folder on the volume Helm ships to: there the descent lands the
            // file back beside itself, `free` reads its own name as taken, and
            // the loop becomes `a 2.jpg`, `a 2 2.jpg` instead.
            let sorted = here.lastPathComponent
                .compare(bucket, options: .caseInsensitive) == .orderedSame
            return move(url, into: sorted ? here : here.appendingPathComponent(bucket),
                        approved: approved)

        case let .rename(pattern):
            return rename(url, pattern: pattern, plan.facts, approved: approved)

        case let .addTag(name):
            return tag(name, on: url)

        case .trash:
            return trash(url, at: path, approved: approved)
        }
    }

    private func rename(_ url: URL, pattern: String, _ facts: FileFacts,
                        approved: PathCanonical.AncestryIdentity?) -> RuleOutcome {
        guard let name = RenamePattern.apply(pattern, to: facts) else {
            return .refused(.badPattern)
        }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        // A pattern can name the file it is renaming — `{name}` does, and so
        // does any pattern mid-edit. Numbering it would make `a.pdf` into
        // `a 2.pdf`, then `a 2 2.pdf`, one file per sweep forever.
        guard target.path != url.path else { return .alreadyDone }
        do {
            // The name reported is the name that landed. They differ exactly
            // in the collision case — which is the case the stamp exists for,
            // so reporting the pattern's name stamped the bystander it
            // collided with and left the moved file unmarked to be renamed
            // again next sweep.
            let landed = free(target, moving: url)
            guard leadsWhereItLed(url.path, approved) else {
                return .refused(.changedSinceCheck)
            }
            try FileManager.default.moveItem(at: url, to: landed)
            return .renamed(to: landed.lastPathComponent)
        } catch {
            return .failed(HelmFailure.describe(error))
        }
    }

    private func tag(_ tag: String, on url: URL) -> RuleOutcome {
        // Tagging follows a symlink and writes to its target, which is a
        // metadata write outside the gate the resolved path would have
        // failed. `WatchScope` resolves, so this only has to refuse the
        // case where the two disagree.
        //
        // Which is also why this arm takes no `leadsWhereItLed`: refusing
        // every path that resolves to something other than its own spelling
        // is the stronger question, it is asked here rather than at the
        // gate, and an ancestor swapped in the window fails it — see
        // `TheActTakesWhatTheGateApprovedTests`.
        guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path
        else { return .refused(.outOfScope) }
        do {
            var values = URLResourceValues()
            var tags = (try url.resourceValues(forKeys: [.tagNamesKey])).tagNames ?? []
            guard !tags.contains(tag) else { return .tagged(tag) }
            tags.append(tag)
            values.tagNames = tags
            var mutable = url
            try mutable.setResourceValues(values)
            return .tagged(tag)
        } catch {
            return .failed(HelmFailure.describe(error))
        }
    }

    private func trash(_ url: URL, at path: String,
                       approved: PathCanonical.AncestryIdentity?) -> RuleOutcome {
        // The engine has the last word on deletion, as everywhere else —
        // and both gates have to say yes: `WatchScope` that a rule may
        // reach here at all, `UserFileScope` that trashing it will not
        // break the machine.
        let (allowed, _) = UserFileScope.partition([path])
        guard !allowed.isEmpty else { return .refused(.outOfScope) }
        guard leadsWhereItLed(path, approved) else { return .refused(.changedSinceCheck) }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return .trashed
        } catch {
            return .failed(HelmFailure.describe(error))
        }
    }

    /// Whether `path` still leads where it led when the gate approved it.
    ///
    /// **The gate and the act resolve the path twice, and a swap between them
    /// belongs to whoever can write in the folder.** `WatchScope.allows`
    /// resolves symlinked ancestors at check time; `moveItem`, `trashItem` and
    /// `setResourceValues` each resolve them again when they run, and in
    /// between sit a `fileExists`, a `createDirectory` and the collision loop.
    /// Measured on the real runner: 1642 of 20,000 attempts carried a file out
    /// of a folder `WatchScope` had refused — and out is the direction that
    /// matters, because Helm holds Full Disk Access and the swapper need not.
    ///
    /// Device and inode of the resolved parent, which is the same recheck
    /// `HelmTrash.remove` carries for the batch removals. **It narrows and does
    /// not close**, for the reason stated there: one stat chain still separates
    /// this from the syscall's own resolve. What it takes away is every wide
    /// part — everything this runner does between the gate and the act is now
    /// behind it.
    ///
    /// A parent that has *gone* counts as changed. The act would fail in any
    /// case, and refusing says which.
    private func leadsWhereItLed(_ path: String,
                                 _ approved: PathCanonical.AncestryIdentity?) -> Bool {
        ancestry(path) == approved
    }

    private func move(_ url: URL, into folder: URL,
                      approved: PathCanonical.AncestryIdentity?) -> RuleOutcome {
        // A destination outside the user's own files is refused however it got
        // into the rule — a rule is a decision made once and executed forever,
        // so the check cannot live in the editor.
        guard WatchScope.allows(folder.path, home: home) else { return .refused(.outOfScope) }
        // A folder cannot be moved inside itself. Reachable without malice: a
        // sorting rule whose conditions eventually match a folder will one day
        // be handed the bucket folder it made itself, and `moveItem` would then
        // fail with EINVAL on every sweep, forever, logging as it went.
        guard !folder.path.hasPrefix(url.path + "/"), folder.path != url.path
        else { return .refused(.outOfScope) }
        // The file is already there, so there is nothing to do and — this is
        // the part that bites — something to avoid doing. `free` would read the
        // file's own name as taken, by the file itself, and number the arrival:
        // `photo.jpg` moved into its own folder becomes `photo 2.jpg`, and
        // `photo 2 2.jpg` the sweep after that. Reachable with one wrong choice
        // in the panel: "every image goes to ~/Downloads", pointed at
        // ~/Downloads. `rename` has said this since it was written; this path
        // was left leaning on the stamp, which `note` tolerates the loss of.
        // Standardized for the trailing slash a typed path carries, and
        // caseless for the same reason `free` is.
        let here = url.deletingLastPathComponent().standardizedFileURL.path
        guard here.compare(folder.standardizedFileURL.path,
                           options: .caseInsensitive) != .orderedSame
        else { return .alreadyDone }
        do {
            // A rule that names a folder is asking for that folder to exist.
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Asked again now that the folder is there: `createDirectory` is
            // content with a symlink that already points somewhere, so a link
            // swapped in over the destination between the gate above and this
            // line is a folder the gate never judged. This is also what makes
            // the reading below a reference and not a guess — a destination
            // that did not exist when the gate ran has no identity to compare
            // against, and taking it before creation would refuse every first
            // arrival into a bucket.
            guard WatchScope.allows(folder.path, home: home) else {
                return .refused(.outOfScope)
            }
            let landing = folder.appendingPathComponent(url.lastPathComponent)
            let approvedDestination = ancestry(landing.path)
            let target = free(landing)
            // Both ends, with the move one statement away: the source, because
            // `moveItem` resolves it again and would carry a vault's file out;
            // the destination, because the collision loop above is a window
            // whose width the swapper sets by filling the folder with names.
            guard leadsWhereItLed(url.path, approved),
                  leadsWhereItLed(target.path, approvedDestination)
            else { return .refused(.changedSinceCheck) }
            try FileManager.default.moveItem(at: url, to: target)
            return .moved(to: target.path)
        } catch {
            return .failed(HelmFailure.describe(error))
        }
    }

    /// A name nothing is using yet. Overwriting is the one failure this module
    /// could commit that nobody can undo, so an arriving file is numbered
    /// — `a 2.pdf` — the way the Finder numbers a copy.
    /// A name nothing else is holding — `moving` excepted, which is the file
    /// being renamed.
    ///
    /// On a case-insensitive volume `report.pdf` and `REPORT.pdf` are one name,
    /// so asking for the second found the first "taken" — by the very file
    /// being renamed — and produced `REPORT 2.pdf`. The person asked for
    /// capitals, not for a second file.
    private func free(_ url: URL, moving from: URL? = nil) -> URL {
        if let from, url.path.compare(from.path, options: .caseInsensitive) == .orderedSame {
            return url
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for index in 2...999 {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}
