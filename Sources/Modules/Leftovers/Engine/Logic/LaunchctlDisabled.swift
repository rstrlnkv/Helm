import Foundation

/// Turning a login item off without deleting it.
///
/// macOS keeps a per-user list of disabled launchd labels — the same one the
/// system's own Login Items switches write. Using it means Helm changes
/// nothing on disk, the choice survives a reboot, and the user can undo it
/// here or in System Settings. The alternative, moving someone's plist
/// somewhere else, is a change they cannot see and we cannot promise to undo.
public enum LaunchctlDisabled {
    /// Labels currently switched off, from `launchctl print-disabled gui/<uid>`:
    ///     "com.acme.helper" => disabled
    public static func parse(_ output: String) -> Set<String> {
        var disabled: Set<String> = []
        for line in output.split(separator: "\n") {
            guard line.contains("=> disabled"),
                  let start = line.firstIndex(of: "\""),
                  let end = line[line.index(after: start)...].firstIndex(of: "\"")
            else { continue }
            disabled.insert(String(line[line.index(after: start)..<end]))
        }
        return disabled
    }

    /// Agents run in the user's domain — no password needed. Daemons need
    /// root, and Apple's own agents are not ours to stop.
    public static func canToggle(kind: StaleKind, status: ItemStatus,
                                 identifier: String) -> Bool {
        guard kind == .launchAgent, !identifier.isEmpty else { return false }
        return !identifier.hasPrefix("com.apple.")
    }
}
