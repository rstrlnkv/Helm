import Foundation

/// Everything the Hosts & Keys engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an
/// arm is a build error rather than a command that silently answers nothing.
public enum HostsCommand: String, CaseIterable, Sendable {
    /// Read the files and emit the state. Sent when the page appears.
    case load
    /// Write `/etc/hosts`. One password dialog, one batch of edits.
    case applyHosts
    /// Put a backup back, through the same privileged path.
    case restoreHosts
    /// Write `~/.ssh/config`. No dialog: it is the person's own file.
    case applySSHConfig
    case settingsChanged
}

/// Everything the engine says about itself.
///
/// **Two names, not one.** The transport replays the last event *per name*: a
/// page reopened mid-write must receive both the snapshot and «a write is in
/// flight», and a single slot hands it whichever arrived last. Homebrew learned
/// this with `opLog` against `opState`.
public enum HostsEvent: String, Sendable {
    case state
    case operation
}

/// What `applyHosts` carries: the whole file, as the person means it to be.
///
/// Declared once, here, in the engine's `Logic/`. The UI target imports the
/// engine and reads this type; a matching struct restated on the view-model
/// side would be a wire contract with no compiler between its halves, which
/// already cost this app a `force: Bool?` against a `force: Bool`.
public struct HostsApply: Codable, Sendable {
    public let text: String
    public init(text: String) { self.text = text }
}

/// What `restoreHosts` carries: which backup.
public struct HostsRestore: Codable, Sendable {
    public let backupID: String
    public init(backupID: String) { self.backupID = backupID }
}

/// What `applySSHConfig` carries: the whole file, as the person means it to be.
///
/// Its own type rather than `HostsApply` reused. The two payloads have the same
/// shape today and mean different things — one is bound for a file owned by
/// root through a privileged sentence, the other for a file in the person's own
/// home — and a type that means two things is the shape this house splits on
/// sight. It also stops a command's payload being decoded by the wrong arm and
/// looking plausible.
public struct SSHConfigApply: Codable, Sendable {
    public let text: String
    public init(text: String) { self.text = text }
}

/// What writing the config came to.
///
/// Four answers rather than a `Bool`, because the page says a different sentence
/// for each and two of them are not failures of the write at all: `outOfScope`
/// is Helm refusing to follow a path out of the home directory, and
/// `notVerified` is a write that reported success over a file that did not
/// change.
public enum SSHConfigOutcome: String, Codable, Sendable {
    case applied
    case failed
    case notVerified
    case outOfScope
}
