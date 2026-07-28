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

    public enum Refusal: String, Equatable, Sendable {
        /// The file or the destination is not the user's to move.
        case outOfScope
        /// A rename pattern the filesystem should not be asked to take.
        case badPattern
        case missing
    }
}

/// The plan, performed. One file at a time, and every path through it either
/// does exactly one thing or does nothing and says why.
public struct RuleRunner: Sendable {
    /// Which home `WatchScope` measures against. Injected so a test can put its
    /// fixtures somewhere real without writing into the person's own folders —
    /// the gate is the same gate, asked about a different home.
    private let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    public func run(_ plan: RulePlan, at path: String) -> RuleOutcome {
        guard FileManager.default.fileExists(atPath: path) else { return .refused(.missing) }
        // Asked before anything happens, so a file already handled by this rule
        // costs a stat rather than a move.
        guard !RuleStamp.isStamped(path, by: plan.rule.id) else { return .alreadyDone }
        // The file itself has to be somewhere a rule may reach, whatever the
        // rule says — the rules are JSON in a plist any process can write, so
        // this is the only place the question is settled. `WatchScope` rather
        // than `UserFileScope`: the shared gate answers "may this be trashed
        // without breaking the machine", which says yes to `~/Library/Messages`
        // and to `~/Library/LaunchAgents`.
        guard WatchScope.allows(path, home: home) else { return .refused(.outOfScope) }

        let outcome = perform(plan, at: path)
        switch outcome {
        case .refused, .failed, .alreadyDone:
            break
        case let .moved(to: destination):
            // Stamped where it landed: the mark travels with a move, but the
            // path we know is the old one.
            note(destination, plan)
        case let .renamed(to: name):
            note((path as NSString).deletingLastPathComponent + "/" + name, plan)
        case .tagged:
            note(path, plan)
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
    private func note(_ path: String, _ plan: RulePlan) {
        guard !RuleStamp.stamp(path, by: plan.rule.id) else { return }
        HelmLog.shared.warn("autopilot", "could not stamp \(Redact.path(path))")
    }

    private func perform(_ plan: RulePlan, at path: String) -> RuleOutcome {
        let url = URL(fileURLWithPath: path)
        switch plan.action {
        case let .move(to: destination):
            return move(url, into: URL(fileURLWithPath: destination))

        case let .sortIntoSubfolder(scheme):
            let bucket = SortBucket.name(for: plan.facts, scheme: scheme)
            let here = url.deletingLastPathComponent()
            // A file already in its bucket has arrived. The bucket used to be
            // hung off the parent unconditionally, so `Images/a.jpg` was
            // offered `Images/Images/`, and the only thing standing between
            // that and a file buried a level deeper every hour was the stamp
            // — which `note` explicitly tolerates the loss of. `setxattr`
            // answers `ENOTSUP` on exFAT and `WatchScope` admits `/Volumes`,
            // so the tolerated case is an ordinary USB stick.
            //
            // Compared without case, because `images` and `Images` are one
            // folder on the volume Helm ships to: there the descent lands the
            // file back beside itself, `free` reads its own name as taken, and
            // the loop becomes `a 2.jpg`, `a 2 2.jpg` instead.
            let sorted = here.lastPathComponent
                .compare(bucket, options: .caseInsensitive) == .orderedSame
            return move(url, into: sorted ? here : here.appendingPathComponent(bucket))

        case let .rename(pattern):
            guard let name = RenamePattern.apply(pattern, to: plan.facts) else {
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
                try FileManager.default.moveItem(at: url, to: landed)
                return .renamed(to: landed.lastPathComponent)
            } catch {
                return .failed(HelmFailure.describe(error))
            }

        case let .addTag(tag):
            // Tagging follows a symlink and writes to its target, which is a
            // metadata write outside the gate the resolved path would have
            // failed. `WatchScope` resolves, so this only has to refuse the
            // case where the two disagree.
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

        case .trash:
            // The engine has the last word on deletion, as everywhere else —
            // and both gates have to say yes: `WatchScope` that a rule may
            // reach here at all, `UserFileScope` that trashing it will not
            // break the machine.
            let (allowed, _) = UserFileScope.partition([path])
            guard !allowed.isEmpty else { return .refused(.outOfScope) }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                return .trashed
            } catch {
                return .failed(HelmFailure.describe(error))
            }
        }
    }

    private func move(_ url: URL, into folder: URL) -> RuleOutcome {
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
            let target = free(folder.appendingPathComponent(url.lastPathComponent))
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
