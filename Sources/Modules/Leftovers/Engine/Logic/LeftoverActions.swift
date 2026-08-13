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

/// Why Helm is not offering to delete something, in the two shapes that answer a
/// different question for the person reading the row: one is a permission somebody
/// on this Mac has, the other is a decision of Apple's that nobody here can take
/// back.
public enum NoDelete: Equatable, Sendable {
    case needsAdministrator, protectedByMacOS
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

    /// Why this row has no delete button — or nil, when it has one.
    ///
    /// **Because «Needs an administrator to delete» was drawn where no
    /// administrator can help.** The row's menu said it for everything without
    /// `.delete`, and `available` withholds that from `com.apple.*` and from
    /// `.protectedItem` too: files the rule will not release at any password. The
    /// one line the page offers instead of a button was sending people to find
    /// one.
    ///
    /// Asked of `available` rather than restating its conditions, so the two
    /// cannot come to disagree about which rows have a button — the disagreement
    /// `StaleItem.removable` records paying for once already.
    public static func whyDeleteIsWithheld(from item: StaleItem) -> NoDelete? {
        guard !available(for: item).contains(.delete) else { return nil }
        // A system extension is not a file: macOS removes it with the app that
        // installed it and SIP refuses everyone else. The row draws «Manage…»
        // instead of this menu, and the answer is still the honest one.
        if item.kind == .systemExtension { return .protectedByMacOS }
        if item.identifier.hasPrefix("com.apple.") || item.status == .protectedItem {
            return .protectedByMacOS
        }
        // What is left is a folder Helm cannot write in, or a daemon whose
        // unloading needs root: both are things an administrator really can do.
        return .needsAdministrator
    }

    /// Clearing a leftover is tidying; deleting something the Mac is currently
    /// loading is a decision, and the app may put it back on next launch.
    public static func needsConfirmation(_ item: StaleItem) -> Bool {
        item.status != .orphaned
    }
}
