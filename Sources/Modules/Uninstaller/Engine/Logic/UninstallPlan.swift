import Foundation

/// One app queued for removal, with the files found for it. The review screen
/// shows these grouped per app; the plan turns them into paths to trash.
public struct UninstallGroup: Identifiable, Equatable, Sendable {
    public var id: String { app.bundleID }
    public let app: InstalledApp
    public let leftovers: [Leftover]
    public let running: Bool

    public init(app: InstalledApp, leftovers: [Leftover], running: Bool) {
        self.app = app
        self.leftovers = leftovers
        self.running = running
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
    public static func paths(_ groups: [UninstallGroup], selectedLeftovers: Set<String>) -> [String] {
        groups.flatMap { group in
            [group.app.path] + group.leftovers.map(\.path).filter { selectedLeftovers.contains($0) }
        }
    }

    public static func totalBytes(_ groups: [UninstallGroup], selectedLeftovers: Set<String>) -> Int {
        groups.reduce(0) { sum, group in
            sum + group.app.sizeBytes
                + group.leftovers.filter { selectedLeftovers.contains($0.path) }
                    .reduce(0) { $0 + $1.sizeBytes }
        }
    }

    public static func allLeftoverPaths(_ groups: [UninstallGroup]) -> [String] {
        groups.flatMap { $0.leftovers.map(\.path) }
    }
}
