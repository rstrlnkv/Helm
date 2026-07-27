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

    public init() {}

    public func run(_ plan: RulePlan, at path: String) -> RuleOutcome {
        guard FileManager.default.fileExists(atPath: path) else { return .refused(.missing) }
        // Asked before anything happens, so a file already handled by this rule
        // costs a stat rather than a move.
        guard !RuleStamp.isStamped(path, by: plan.rule.id) else { return .alreadyDone }
        // The file itself has to be the user's, whatever the rule says. This is
        // the same gate the duplicate finder and the disk module use, and it is
        // here — in the engine — rather than in whatever built the plan.
        guard UserFileScope.isRemovable(path) else { return .refused(.outOfScope) }

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
        case .tagged, .trashed:
            note(path, plan)
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
        HelmLog.shared.warn("rules", "could not stamp \(Redact.path(path))")
    }

    private func perform(_ plan: RulePlan, at path: String) -> RuleOutcome {
        let url = URL(fileURLWithPath: path)
        switch plan.action {
        case let .move(to: destination):
            return move(url, into: URL(fileURLWithPath: destination))

        case let .sortIntoSubfolder(scheme):
            let bucket = SortBucket.name(for: plan.facts, scheme: scheme)
            return move(url, into: url.deletingLastPathComponent()
                .appendingPathComponent(bucket))

        case let .rename(pattern):
            guard let name = RenamePattern.apply(pattern, to: plan.facts) else {
                return .refused(.badPattern)
            }
            let target = url.deletingLastPathComponent().appendingPathComponent(name)
            do {
                try FileManager.default.moveItem(at: url, to: free(target))
                return .renamed(to: name)
            } catch {
                return .failed(HelmFailure.describe(error))
            }

        case let .addTag(tag):
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
            // The engine has the last word on deletion, as everywhere else.
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
        guard UserFileScope.isRemovable(folder.path) else { return .refused(.outOfScope) }
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
    private func free(_ url: URL) -> URL {
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
