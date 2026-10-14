import Foundation

/// `~/.ssh/config`: read and written by the person's own account.
///
/// **The file belongs to whoever is logged in, so a write is a write.** What
/// stands between a text field and the disk is `SSHFileScope`, and the engine
/// asks it — a port cannot be trusted to gate itself when a fake stands where
/// it stands.
///
/// `url` is on the protocol because the gate judges a path, not a handle: the
/// engine has to be able to ask «where would this write land» before letting
/// one happen.
public protocol SSHConfigPort: Sendable {
    /// Where this port reads and writes.
    var url: URL { get }
    /// The text, or nil when the file is missing or is not UTF-8 — two states
    /// folded into one, neither of them an empty file: an empty config is a
    /// thing a person may mean.
    func read() -> String?
    /// Writes the text back, answering whether the write itself reported
    /// success. **Reporting success is not evidence the file changed** — the
    /// engine reads back and compares.
    func write(_ text: String) -> Bool
}

/// `~/.ssh` itself: what is in it, what its modes are, and the one write this
/// module makes to a key — `chmod`.
///
/// **Every name crossing this protocol is a bare file name, never a path.** A
/// name reaches the engine from a payload, so a `..` in one must not be able to
/// become a directory on the way to a `chmod`. The implementations refuse a name that is
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
    /// What is in the directory and which of those names are directories, or
    /// nil when the directory could not be read at all — missing, or one this
    /// process may not search. Nil is not an empty directory: a Mac with no keys
    /// yet is a page that says «no keys», and a directory nobody could open is a
    /// page that must say something else.
    ///
    /// The directory flag rides with the listing rather than being asked per
    /// name: it is one question about the group, and `KeyInventory.Listing`
    /// carries why it has to be asked at all.
    func names() -> KeyInventory.Listing?
    /// The readings behind one row. Gathered here because they come from
    /// several different system calls; decided in `KeyRow.row(from:agent:)`,
    /// which is pure and can be asked about the missing ones.
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
    /// Put the key in, answering the prompt with `secret` — empty when nobody
    /// has typed one yet.
    ///
    /// **The tool's own question is how this app learns the key is encrypted.**
    /// The alternative was a probe — `ssh-keygen -y -P '' -f` — run over every
    /// key on every refresh, which is a second subprocess per row for a fact
    /// the load itself already surfaces. So there is one path: run it, and if
    /// `ssh-add` asked for a passphrase, say so.
    ///
    /// `secret` is `inout` and is zeroed by the implementation, the way
    /// `KeyGeneratorPort.generate` is: after this returns the caller's buffer
    /// holds nothing.
    func load(_ name: String, answering secret: inout Data) -> AgentLoad
    func unload(_ name: String) -> Bool
}

/// What a load came to. **Three answers, and the middle one is the point** —
/// «it failed» over a key that is merely locked sends a person looking at their
/// key, and the key is fine.
public enum AgentLoad: String, Codable, Sendable, Equatable {
    case loaded
    /// `ssh-add` asked for a passphrase. Either none was given, or the one
    /// given was not accepted; the page knows which because it knows what it
    /// sent.
    case needsPassphrase
    case failed
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

/// `~/.ssh/known_hosts`: the hosts already trusted, read and pruned.
///
/// The same shape as `SSHConfigPort` and for the same reasons — the file
/// belongs to the person, so a write is a write and what stands between a text
/// field and the disk is `SSHFileScope` plus the read-back. It is
/// its own protocol rather than a second pair of methods on that one: two files
/// behind one port is a fake that cannot be broken for one of them, and the
/// engine would have no way to say which file a refusal was about.
public protocol KnownHostsPort: Sendable {
    var url: URL { get }
    /// The text, or nil when the file is missing or is not UTF-8. A Mac that
    /// has never connected anywhere has no such file, and that is not an empty
    /// one.
    func read() -> String?
    func write(_ text: String) -> Bool
}
