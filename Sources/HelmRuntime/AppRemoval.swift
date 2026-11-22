import Foundation

/// The vocabulary of removing one application on behalf of another module.
///
/// The Uninstaller is the only module that knows what an app owns on disk, so a module that
/// wants an app gone (Launchpad's edit mode) asks it through `AppRemovalService` and never
/// reaches `HelmTrash` itself. Nothing here names a module: the host hands the service over
/// through the descriptor (`ModuleDescriptor.appRemoval`), and the Uninstaller's engine is
/// the one that judges, so a caller that forgot to ask cannot widen what is removed.
///
/// **No path crosses back out.** The report carries reasons and a byte count; a person's apps
/// are not for a caller's log or notice to name.
public struct AppRemovalCandidate: Equatable, Sendable {
    public let bundleID: String
    public let path: String
    public let name: String

    public init(bundleID: String, path: String, name: String) {
        self.bundleID = bundleID; self.path = path; self.name = name
    }
}

/// Whether the Uninstaller itself would offer this app, read when it is asked and read again
/// by `preview` and `remove` before anything is scanned or quit.
public enum AppRemovalVerdict: Equatable, Sendable {
    case removable
    case refused(Refusal)

    public enum Refusal: Equatable, Sendable {
        /// macOS's own (`com.apple.` id).
        case system
        /// Not an app the Uninstaller lists: another folder, a link, a bundle whose
        /// `Info.plist` no longer says what the candidate said, a path the removal gate refuses.
        case notOffered
        /// Not there any more.
        case gone
        /// The Uninstaller is stopped; nothing was asked of it.
        case stopped
    }
}

/// What a removal would take, for the confirmation: the app, what is certainly its own
/// (leftovers found by bundle id, never by name) and whether it is up now.
public struct AppRemovalPreview: Equatable, Sendable {
    /// `nil`: the measure did not finish in time; the card says no size rather than a wrong one.
    public let appBytes: Int?
    public let leftoverCount: Int
    public let leftoverBytes: Int
    public let running: Bool

    public init(appBytes: Int?, leftoverCount: Int, leftoverBytes: Int, running: Bool) {
        self.appBytes = appBytes; self.leftoverCount = leftoverCount
        self.leftoverBytes = leftoverBytes; self.running = running
    }
}

/// `preview`'s answer: the preview, or the reason there is none.
public enum AppRemovalAsk: Equatable, Sendable {
    case ready(AppRemovalPreview)
    case refused(AppRemovalVerdict.Refusal)
}

public struct AppRemovalReport: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The app and everything with it is in the Trash.
        case moved
        /// The app is in the Trash and something of its own is not (`failed`).
        case movedWithFailures
        /// Nothing moved: the app is up and no quit was agreed, or it is still up after the quit.
        case stillRunning
        /// The app did not move: the verdict refused it, or macOS did (`failed` holds why).
        case refused
        /// Another removal is in flight.
        case busy
        /// The Uninstaller is stopped.
        case stopped
    }

    public let outcome: Outcome
    public let freedBytes: Int
    /// One reason per path that refused, the app's own included.
    public let failed: [TrashFailure.Reason]

    public init(_ outcome: Outcome, freedBytes: Int = 0, failed: [TrashFailure.Reason] = []) {
        self.outcome = outcome; self.freedBytes = freedBytes; self.failed = failed
    }
}

/// The door. Resolved at each use (`LaunchpadDescriptor`), because the module behind it can be
/// switched off between two uses.
@MainActor public protocol AppRemovalService: AnyObject {
    /// One verdict per candidate, in order. A stopped service answers `.refused(.stopped)` for each.
    func verdicts(for candidates: [AppRemovalCandidate]) async -> [AppRemovalVerdict]
    func preview(_ candidate: AppRemovalCandidate) async -> AppRemovalAsk
    /// `quittingIfRunning`: the person agreed that the app is quit without saving.
    func remove(_ candidate: AppRemovalCandidate, quittingIfRunning: Bool) async -> AppRemovalReport
}
