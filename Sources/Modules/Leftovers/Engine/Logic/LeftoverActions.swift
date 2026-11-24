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

/// Why the row asks before deleting, in the two shapes that put a different fact
/// in front of the person: the Mac is loading this one, or Helm could not read it.
/// Beside `NoDelete` because it is the same kind of answer — a reason the page
/// turns into a sentence — read by `askBeforeDeleting` below.
public enum AskFirst: Equatable, Sendable {
    case loadedNow, cannotBeRead, cannotBeChecked
}

public enum LeftoverActions {
    /// Apple's own job, or one the scan marked protected: the one test both
    /// `available(for:)` and `whyDeleteIsWithheld(from:)` stand on, so the page
    /// cannot offer what the reason below says is withheld.
    private static func isApplesOrProtected(_ item: StaleItem) -> Bool {
        item.identifier.hasPrefix("com.apple.") || item.status == .protectedItem
    }

    /// **One argument, and it is the item.** A second parameter carrying what the
    /// item already carries (`writable:`) would buy only the ability to disagree,
    /// and a test could describe a shape a scan cannot produce.
    static func available(for item: StaleItem) -> Set<LeftoverAction> {
        // **A source row is a folder the scan did not read, not a file it found.**
        // Nothing below is true of one: there is no file to move, no label to
        // switch and no owner to judge. Looking at it is the one thing left, and
        // it is what a person told «Helm did not read this folder» wants to do.
        if item.status.isSource { return [.reveal] }
        if item.kind == .systemExtension { return [.systemSettings] }
        if isApplesOrProtected(item) {
            return [.reveal]
        }
        var actions: Set<LeftoverAction> = [.reveal]
        // **The switch needs a label that is the job's, and one launchctl will
        // take.** `LaunchLabel.mayBeSwitched` is the second half and the same
        // predicate `LeftoversEngine` guards on before it acts, so the page and the
        // engine cannot disagree about a row — and it is where «a file may claim
        // another job's label» is refused. The first half is `.unreadable`: the
        // identifier is then the file's own name, an invention for a job whose
        // contents never came, and disabling an invented label writes an entry the
        // next scan reads back as «Disabled».
        // **And a label two files claim is one switch, not two.** Both copies of
        // `com.vendor.updater` pass `mayBeSwitched`, so «Turn off» would be drawn
        // twice for one `launchctl disable`. `LaunchClaims` says why neither may
        // carry it, and the row names the other file instead.
        if item.kind == .launchAgent, item.status != .unreadable,
           item.labelAlsoClaimedBy == nil,
           LaunchLabel.mayBeSwitched(label: item.identifier, path: item.path) {
            actions.insert(.turnOff)
        }
        if item.kind != .launchDaemon, item.writable { actions.insert(.delete) }
        return actions
    }

    /// Why this row has no delete button — or nil, when it has one.
    ///
    /// **Not «Needs an administrator to delete» where no administrator can
    /// help**: `available` withholds `.delete` from `com.apple.*` and from
    /// `.protectedItem` too, files the rule will not release at any password.
    ///
    /// Asked of `available` rather than restating its conditions, so the two
    /// cannot disagree about which rows have a button.
    public static func whyDeleteIsWithheld(from item: StaleItem) -> NoDelete? {
        // **A source row has no answer here, because it is not a file.** Neither
        // sentence is true of a folder the scan did not read: no administrator can
        // help, and macOS is not protecting it. Nil is «no sentence», and the page
        // draws neither the button nor a reason for such a row
        // (`LeftoversSettingsPage.controls`). The invariant the other rows keep —
        // a reason exactly where the button is not — is a rule about rows that
        // stand for files.
        guard !item.status.isSource else { return nil }
        guard !available(for: item).contains(.delete) else { return nil }
        // A system extension is not a file: macOS removes it with the app that
        // installed it and SIP refuses everyone else. The row draws the button
        // that opens the pane instead of this menu, and the answer is still the
        // honest one.
        if item.kind == .systemExtension || isApplesOrProtected(item) { return .protectedByMacOS }
        // What is left is a folder Helm cannot write in, or a daemon whose
        // unloading needs root: both are things an administrator really can do.
        return .needsAdministrator
    }

    /// Why Helm asks before deleting this one — or nil, when it does not ask.
    ///
    /// Clearing a leftover is tidying; deleting something the Mac is currently
    /// loading is a decision, and the app may put it back on next launch. The page
    /// asks this one rule for both the ellipsis and the dialog, so it cannot dim
    /// one on one rule and word the other from another.
    ///
    /// The shape `whyDeleteIsWithheld` uses: «loaded now» is a claim about
    /// contents, and false of a job whose plist Helm never got to read.
    ///
    /// Exhaustive over the status: a further one must be a build error here rather
    /// than inherit whichever sentence sits nearest.
    public static func askBeforeDeleting(_ item: StaleItem) -> AskFirst? {
        switch item.status {
        case .orphaned: return nil
        case .inUse: return .loadedNow
        // Never reached — `available` withholds `.delete` from a protected row,
        // so no dialog is drawn for one. It answers the same as `.inUse` rather
        // than nil because the honest reading of a protected item is that macOS
        // is using it, and a nil here would say «delete this without asking».
        case .protectedItem: return .loadedNow
        case .unreadable: return .cannotBeRead
        // The file was read; what could not be read is elsewhere — the program it
        // points at, or macOS's own list of what is loaded. «Loaded now» would
        // claim the reading that failed, and «could not read this file» would
        // blame the file.
        case .undetermined: return .cannotBeChecked
        // Never reached — `available` withholds every act from a source row, and
        // no dialog is drawn for one. It answers rather than returning nil for the
        // reason `.protectedItem` does: nil here says «delete this without
        // asking», and «Helm could not check whether anything still uses it» is
        // the plain truth about a folder it never opened.
        case .sourceRedirected, .sourceUnreadable: return .cannotBeChecked
        }
    }
}
