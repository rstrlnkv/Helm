import Foundation

/// Which of Helm's four moves apply to one item.
///
/// The rules are the system's, not ours:
///   • launchd's disabled list works in the user's own domain, so an agent can
///     be switched off without a password — even one installed for every user.
///   • Deleting means moving a file, which needs write access to the folder it
///     sits in. /Library belongs to root; the user's own Library does not.
///   • Daemons load in the system domain: switching one off needs root, so the
///     row offers nothing rather than a button that always fails.
///   • A system extension is not a file at all. macOS removes it with the app
///     that installed it, and SIP blocks anyone else from uninstalling it.
public enum LeftoverAction: Hashable, Sendable {
    case turnOff, delete, reveal, systemSettings
}

public enum LeftoverActions {
    /// **One argument, and it is the item.**
    ///
    /// This took `writable:` beside the item that already carries it, and every
    /// caller in the app passed `item.writable` because there is nothing else to
    /// pass. What the parameter bought was the ability to disagree: a test could
    /// — and did — hand over an item whose own `writable` was true and ask what
    /// the actions are when it is false, so the assertion described a shape a
    /// scan cannot produce. `LaunchctlDisabled.canToggle` was deleted for the
    /// same family of reason, one argument the other way round: it took a
    /// `status` and never read it.
    public static func available(for item: StaleItem) -> Set<LeftoverAction> {
        if item.kind == .systemExtension { return [.systemSettings] }
        if item.identifier.hasPrefix("com.apple.") || item.status == .protectedItem {
            return [.reveal]
        }
        var actions: Set<LeftoverAction> = [.reveal]
        if item.kind == .launchAgent, !item.identifier.isEmpty { actions.insert(.turnOff) }
        if item.kind != .launchDaemon, item.writable { actions.insert(.delete) }
        return actions
    }

    /// Clearing a leftover is tidying; deleting something the Mac is currently
    /// loading is a decision, and the app may put it back on next launch.
    public static func needsConfirmation(_ item: StaleItem) -> Bool {
        item.status != .orphaned
    }
}
