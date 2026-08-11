import Foundation

/// One app queued for removal, with the files found for it. The review screen
/// shows these grouped per app; the plan turns them into paths to trash.
public struct UninstallGroup: Identifiable, Equatable, Sendable {
    /// The copy on disk, not the bundle id. Two builds of one app — a Setapp
    /// copy beside a direct download — share an id and are two rows, and
    /// `ForEach` given one identity for two draws one of them.
    public var id: String { app.path }
    public let app: InstalledApp
    public let leftovers: [Leftover]
    public let running: Bool

    public init(app: InstalledApp, leftovers: [Leftover], running: Bool) {
        self.app = app
        self.leftovers = leftovers
        self.running = running
    }
}

/// One line of the review screen.
///
/// The bundle is a row rather than a header ornament because the screen has to
/// say what it takes, and `paths` always takes it — see `reviewRows`.
public enum ReviewRow: Equatable, Sendable, Identifiable {
    case bundle(app: InstalledApp)
    case leftover(Leftover)

    public var id: String {
        switch self {
        case .bundle(let app): return app.path
        case .leftover(let leftover): return leftover.path
        }
    }

    /// A checkbox is an offer to decline, and the bundle cannot be declined:
    /// removing an app without removing the app is not a thing this screen does.
    public var isTickable: Bool {
        if case .leftover = self { return true }
        return false
    }

}

/// Pure rules behind the batch uninstall flow.
public enum UninstallPlan {
    public enum Readiness: Equatable, Sendable {
        case ready
        case empty
        /// Names of apps that are still running; removing them needs a quit.
        case needsQuit([String])
    }

    /// A running app holds open files and would come back on relaunch, so it
    /// blocks removal until the user agrees to force-quit it.
    public static func readiness(_ groups: [UninstallGroup], forceQuit: Bool) -> Readiness {
        guard !groups.isEmpty else { return .empty }
        let running = groups.filter(\.running).map(\.app.name)
        guard running.isEmpty || forceQuit else { return .needsQuit(running) }
        return .ready
    }

    /// Bundles always go; leftovers only when ticked on the review screen.
    /// Deduplicated in order: a prefix glob and an exact candidate can resolve
    /// to the same directory, and trashing it twice makes the second attempt
    /// fail with "doesn't exist" — a failure the user can do nothing about.
    public static func paths(_ groups: [UninstallGroup], selectedLeftovers: Set<String>) -> [String] {
        var seen: Set<String> = []
        return groups.flatMap { group in
            ([group.app.path] + group.leftovers.map(\.path).filter { selectedLeftovers.contains($0) })
                .filter { seen.insert($0).inserted }
        }
    }

    /// What one group shows, bundle first.
    ///
    /// The screen used to draw `group.leftovers` alone, so the one path every
    /// removal is certain to take was the only one nobody was shown. Built here
    /// rather than in the view so that what is displayed and what `paths`
    /// returns are two readings of the same rule.
    public static func reviewRows(_ group: UninstallGroup) -> [ReviewRow] {
        [.bundle(app: group.app)] + group.leftovers.map { .leftover($0) }
    }

    public static func totalBytes(_ groups: [UninstallGroup], selectedLeftovers: Set<String>) -> Int {
        var seen: Set<String> = []
        return groups.reduce(0) { sum, group in
            var subtotal = seen.insert(group.app.path).inserted ? group.app.sizeBytes : 0
            for leftover in group.leftovers where selectedLeftovers.contains(leftover.path) {
                if seen.insert(leftover.path).inserted { subtotal += leftover.sizeBytes }
            }
            return sum + subtotal
        }
    }

    /// The leftovers the review screen may arrive with already ticked.
    ///
    /// A path found under the app's *bundle id* is that app's, near enough to
    /// certain. A path found under its *display name* — `Application Support/
    /// <Name>`, `Logs/<Name>` — is a guess, and names collide: "Mail", "Notes",
    /// "Player". A guess arriving pre-ticked next to a Trash button means the
    /// user has to notice it to keep their data; unticked, they have to notice
    /// it to lose it. Same information, opposite default.
    public static func defaultSelection(_ groups: [UninstallGroup]) -> [String] {
        var seen: Set<String> = []
        return groups.flatMap { $0.leftovers }
            .filter { !$0.matchedByName }
            .map(\.path)
            .filter { seen.insert($0).inserted }
    }
}
