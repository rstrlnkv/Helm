import Foundation

/// What `ssh-add -l` says, as **three** answers rather than a list that may be
/// empty.
///
/// The tool folds two very different states into one exit code family, and a
/// reader that keeps only the fingerprints cannot tell them apart:
///
/// - **Holding keys.** Exit 0, one line per key.
/// - **Reachable and empty.** Exit 1, «The agent has no identities.» This is a
///   working agent, and the page's answer is «no keys loaded», with load
///   buttons that will work.
/// - **Unreachable.** Exit 2, «Error connecting to agent». There is no agent —
///   `SSH_AUTH_SOCK` is unset, or the socket is dead — and every load button on
///   the page would fail. Drawn as its own state, because «no keys loaded» over
///   a dead agent is an invitation to press something that cannot work.
///
/// This is the `PowerSource.supply()` shape one module over: a port that folds
/// two questions into one answer leaves a branch nobody can reach.
/// `Codable` because it travels in the state: the badge on a row and the
/// sentence about the agent are the engine's one reading, not a second parse of
/// the same output on the far side of the wire.
public enum AgentList: Codable, Equatable, Sendable {
    case holding([String])
    case empty
    case unreachable

    /// Read from the exit status **and** the output, because neither alone is
    /// enough: exit 1 with fingerprints is not a thing `ssh-add` does, and a
    /// build that trusted the status alone would report an empty agent for any
    /// failure at all.
    public static func read(status: Int32, output: String) -> AgentList {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.isEmpty }
        if status == 0 {
            let fingerprints = lines.compactMap { KeyInventory.described($0)?.fingerprint }
            // Exit 0 with nothing readable in it is not «holding nothing»: it is
            // a tool whose output this build cannot parse, and saying «empty»
            // would be a claim about somebody's agent made out of a parse
            // failure.
            return fingerprints.isEmpty ? .unreachable : .holding(fingerprints)
        }
        // The two failures are told apart by what the tool says, because both
        // are non-zero and macOS's `ssh-add` has used 1 and 2 for them in
        // different releases.
        let said = output.lowercased()
        if said.contains("no identities") { return .empty }
        return .unreachable
    }

    /// Whether a given key is in the agent right now — the badge on a row.
    public func holds(_ fingerprint: String) -> Bool {
        if case .holding(let fingerprints) = self { return fingerprints.contains(fingerprint) }
        return false
    }
}
