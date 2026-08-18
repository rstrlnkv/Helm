import Foundation
import HelmRuntime

/// Reading the file. Separate from writing it because the two need different
/// rights, and a type that can do both invites code that assumes it may.
public protocol HostsFilePort: Sendable {
    /// The file's text, or `nil` if it could not be read at all.
    ///
    /// **`nil` is two states, and neither of them is an empty file:** the file
    /// is not there, and the file is there and is not UTF-8. The page has to
    /// tell both apart from empty, because an empty `/etc/hosts` is something a
    /// person may legitimately mean to write and the other two are not.
    func read() -> String?
}

/// Asking root. One method, three answers.
public protocol PrivilegedPort: Sendable {
    /// Blocking, for as long as the dialog is on screen — which is however long
    /// the person takes to find their password. Callers hop off the cooperative
    /// pool first.
    func run(_ command: String) -> PrivilegedOutcome
}

/// The copies kept beside the app's own support folder.
///
/// **Every name crossing this protocol is a bare file name, never a path.** The
/// id of a backup reaches the engine from a payload, so a `..` in one must not
/// be able to become a directory on the way to `read` or `delete`; the
/// implementations refuse anything that is not one of this module's own names.
/// That is also what keeps a fake honest — a dictionary answers nothing to
/// `"../x"` for free, and a port that answered the file instead would be a port
/// no fake could stand in for.
public protocol BackupPort: Sendable {
    /// Save `text` under `name`. False if it could not be written — a backup
    /// that silently did not happen is worse than none, because the Apply that
    /// follows believes it exists.
    func save(_ text: String, name: String) -> Bool
    /// Newest last. Only this module's own names; the folder is a real folder
    /// on somebody's disk and what else is in it is theirs.
    func list() -> [String]
    /// Nil for a name that is not there and for one whose bytes are not UTF-8 —
    /// a copy is a candidate to be written back as root, so it is decoded as
    /// strictly as the file itself.
    func read(_ name: String) -> String?
    func delete(_ names: [String])
}

/// `~/.ssh/config`: read and written by the person's own account.
///
/// **No `PrivilegedPort` here, and that is the whole difference from the file
/// next door.** `/etc/hosts` belongs to root and every write is a password
/// dialog; this file belongs to whoever is logged in, so a write is a write.
/// What replaces the dialog as the thing standing between a text field and the
/// disk is `SSHFileScope`, and the engine asks it — a port cannot be trusted to
/// gate itself when a fake stands where it stands.
///
/// `url` is on the protocol because the gate judges a path, not a handle: the
/// engine has to be able to ask «where would this write land» before letting
/// one happen.
public protocol SSHConfigPort: Sendable {
    /// Where this port reads and writes.
    var url: URL { get }
    /// The text, or nil when the file is missing or is not UTF-8 — the same two
    /// states `HostsFilePort.read` folds, for the same reason: an empty config
    /// is a thing a person may mean.
    func read() -> String?
    /// Writes the text back, answering whether the write itself reported
    /// success. **Reporting success is not evidence the file changed** — the
    /// engine reads back and compares, which is the rule `WriteIsVerifiedTests`
    /// holds for the privileged path and which is no less true here.
    func write(_ text: String) -> Bool
}

/// `~/.ssh` itself: what is in it, what its modes are, and the one write this
/// module makes to a key — `chmod`.
///
/// **Every name crossing this protocol is a bare file name, never a path**, the
/// rule `BackupPort` states next door and for the same reason: a name reaches
/// the engine from a payload, so a `..` in one must not be able to become a
/// directory on the way to a `chmod`. The implementations refuse a name that is
/// not a plain component, and the engine independently refuses one that is not
/// among the keys it has just listed. Neither check is the other's excuse.
///
/// **No method here opens a private key**, and there is no method that could:
/// what a row shows comes from the `.pub` file, from `stat` and from
/// `ssh-keygen -l`, and this protocol is the whole surface.
public protocol SSHKeysPort: Sendable {
    /// Where this port reads — the one place a new key's path may be composed
    /// from. On the protocol for the reason `SSHConfigPort.url` is: the engine
    /// has to be able to ask «where would this land» before anything lands.
    var directory: URL { get }
    /// The file names in the directory, or nil when the directory could not be
    /// read at all — missing, or one this process may not search. Nil is not an
    /// empty directory: a Mac with no keys yet is a page that says «no keys»,
    /// and a directory nobody could open is a page that must say something
    /// else.
    func names() -> [String]?
    /// The four readings behind one row. Gathered here because they come from
    /// four different system calls; decided in `KeyRow.row(from:agent:)`, which
    /// is pure and can be asked about the missing ones.
    func facts(for pair: KeyInventory.Pair) -> KeyFacts
    /// `~/.ssh`'s own mode. `sshd` refuses an `authorized_keys` under a
    /// group-writable directory, and the row for the directory is drawn from
    /// this.
    func directoryMode() -> mode_t?
    func chmod(_ name: String, to mode: mode_t) -> Bool
    func chmodDirectory(to mode: mode_t) -> Bool
}

/// `ssh-agent`, asked and told.
///
/// `list()` answers `AgentList`'s three states rather than an array, because
/// «reachable and empty» and «no agent at all» decide whether a load button on
/// the page can work — the `PowerSource.supply()` shape, two modules over.
public protocol SSHAgentPort: Sendable {
    func list() -> AgentList
    /// True when the key went in. An encrypted key prompts for its passphrase,
    /// which this method has no channel for and must not pretend to have: it
    /// answers false, and the passphrase path is `PTYProcess`'s.
    func load(_ name: String) -> Bool
    func unload(_ name: String) -> Bool
}

/// Making a key.
///
/// Its own port rather than a method on `SSHKeysPort`, because it is the only
/// thing in this module that spawns a child and hands it a secret — and because
/// a fake of it has to be able to do something no other fake here does: **sit
/// at the prompt.** A generator that has always already finished makes every
/// «does a second press start a second one?» test vacuous, since the subject is
/// over before the code under test is reached.
public protocol KeyGeneratorPort: Sendable {
    /// Runs the generator with `arguments`, answering its prompts with
    /// `secret`, and answers the child's exit status.
    ///
    /// **The secret is `inout` and is zeroed by the implementation**, so a
    /// caller cannot hold a copy by accident: after this returns there is
    /// nothing in the caller's buffer to leak.
    func generate(_ arguments: [String], answering secret: inout Data) -> Int32
}
