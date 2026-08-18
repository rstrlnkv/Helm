import Foundation
import HelmRuntime

public struct SystemHostsFile: HostsFilePort {
    private let path: String
    public init(path: String = HostsWrite.path) { self.path = path }

    public func read() -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        // **Strict on purpose.** `String(data:encoding:)` answers nil on bytes
        // that are not UTF-8, and it must stay that way: a lossy decode turns
        // every high byte into U+FFFD, and the next Apply writes those
        // replacement characters back over the person's file **as root**,
        // destroying the part Helm could not read. Unreadable reaches the page
        // as unreadable — `HostsState.hostsReadable` tells that apart from
        // empty.
        return String(data: data, encoding: .utf8)
    }
}

public struct SystemPrivileged: PrivilegedPort {
    public init() {}
    public func run(_ command: String) -> PrivilegedOutcome { PrivilegedRun.run(command) }
}

/// Copies in Helm's own support folder.
///
/// The file names somebody's hosts — a fact about their machine — so it goes
/// through `PrivateFile` like everything else that does. The mode belongs to
/// the *write*, not to the file: a hand-rolled `write(options: .atomic)` plus
/// `setAttributes` renames a new inode into place and takes the umask.
public struct SystemBackups: BackupPort {
    private let directory: URL
    public init(directory: URL = HelmSupport.directory.appendingPathComponent("hosts-backups")) {
        self.directory = directory
    }

    /// The one place a name becomes a path, and the gate on the way.
    ///
    /// `BackupName.isOurs` is the whole condition and carries the reasoning.
    /// The engine checks membership of `list()` as well; neither check is the
    /// other's excuse — that one is about *which* backup, this one about
    /// whether a name is a name at all, and the second still holds when a
    /// later caller forgets the first.
    private func url(for name: String) -> URL? {
        guard BackupName.isOurs(name) else { return nil }
        return directory.appendingPathComponent(name)
    }

    public func save(_ text: String, name: String) -> Bool {
        guard let url = url(for: name), PrivateFile.directory(at: directory) else { return false }
        return PrivateFile.write(Data(text.utf8), to: url)
    }

    public func list() -> [String] {
        // `contentsOfDirectory` promises no order at all, and the listing *is*
        // the history: `BackupName.pruned` takes the front of it.
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .filter(BackupName.isOurs).sorted() ?? []
    }

    public func read(_ name: String) -> String? {
        guard let url = url(for: name),
              let data = FileManager.default.contents(atPath: url.path) else { return nil }
        // As strict as `SystemHostsFile.read()`, and for the same reason: what
        // comes out of here is a candidate to be written back as root.
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ names: [String]) {
        for name in names {
            guard let url = url(for: name) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Production `SSHConfigPort`: `~/.ssh/config`, read and written as the person.
///
/// **`PrivateFile` writes it**, not a bare `write(options: .atomic)`: the mode
/// belongs to the write rather than to the file — `.atomic` renames a new inode
/// into place, so a fresh write takes the umask — and this is a file `ssh`
/// refuses to use when its mode is too open. That rule is CLAUDE.md's «a file
/// that names somebody's files is written through `PrivateFile`», and a config
/// naming every host somebody connects to is such a file.
public struct SystemSSHConfig: SSHConfigPort {

    public let url: URL

    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ssh/config")) {
        self.url = url
    }

    public func read() -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return PrivateFile.write(data, to: url)
    }
}

/// `~/.ssh` on this Mac.
///
/// **The private half is never opened, and the design of `facts(for:)` is where
/// that is enforced rather than promised.** `ssh-keygen -l -f` reads whichever
/// file it is handed, so it is handed the `.pub`; a pair whose public half has
/// been deleted therefore has no description at all, and the row says so. The
/// alternative — pointing the tool at the private key — would put a passphrase
/// prompt and the key's own bytes inside a listing that runs on every refresh.
public struct SystemSSHKeys: SSHKeysPort {

    public let directory: URL
    /// Bounded, because both tools can sit. `ssh-keygen` on a file on a stalled
    /// network mount does not return, and this runs on every state emission.
    private let deadline: TimeInterval

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ssh"),
                deadline: TimeInterval = 5) {
        self.directory = directory
        self.deadline = deadline
    }

    public func names() -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: directory.path)
    }

    public func facts(for pair: KeyInventory.Pair) -> KeyFacts {
        let path = directory.appendingPathComponent(pair.name).path
        let publicPath = path + ".pub"
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let publicText = pair.hasPublicHalf
            ? (try? Data(contentsOf: URL(fileURLWithPath: publicPath)))
                .flatMap { String(data: $0, encoding: .utf8) }
            : nil
        var described: String?
        if pair.hasPublicHalf {
            let run = HelmProcess.run("/usr/bin/ssh-keygen", ["-l", "-f", publicPath],
                                      timeout: deadline)
            described = run.status == 0 ? run.output : nil
        }
        return KeyFacts(pair: pair,
                        describeLine: described,
                        mode: (attributes?[.posixPermissions] as? NSNumber).map { mode_t($0.uint16Value) },
                        modified: attributes?[.modificationDate] as? Date,
                        publicText: publicText)
    }

    public func directoryMode() -> mode_t? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        return (attributes?[.posixPermissions] as? NSNumber).map { mode_t($0.uint16Value) }
    }

    public func chmod(_ name: String, to mode: mode_t) -> Bool {
        guard let url = url(for: name) else { return false }
        return setMode(mode, at: url.path)
    }

    public func chmodDirectory(to mode: mode_t) -> Bool { setMode(mode, at: directory.path) }

    /// The one place a name becomes a path, and the gate on the way — the same
    /// shape `SystemBackups.url(for:)` carries. A name arrives from a payload,
    /// so it may be a plain component and nothing else: no separator, no `..`,
    /// and not empty. The engine independently refuses a name that is not among
    /// the keys it just listed; that check is about *which* key and this one is
    /// about whether a name is a name at all.
    private func url(for name: String) -> URL? {
        guard !name.isEmpty, !name.contains("/"), name != "..", name != "." else { return nil }
        return directory.appendingPathComponent(name)
    }

    private func setMode(_ mode: mode_t, at path: String) -> Bool {
        do {
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)],
                                                  ofItemAtPath: path)
            return true
        } catch {
            return false
        }
    }
}

/// `ssh-agent`, through `ssh-add`.
///
/// Bounded like the keys port and for a sharper reason: `ssh-add` talks to a
/// socket, and a socket whose other end has gone away is exactly the state this
/// port exists to report — a version of it that hung there would freeze every
/// refresh of the page instead.
public struct SystemSSHAgent: SSHAgentPort {

    private let directory: URL
    private let deadline: TimeInterval

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ssh"),
                deadline: TimeInterval = 5) {
        self.directory = directory
        self.deadline = deadline
    }

    public func list() -> AgentList {
        let run = HelmProcess.run("/usr/bin/ssh-add", ["-l"], timeout: deadline)
        // A timeout is not an empty agent and not a full one: `AgentList.read`
        // is given the status it can only read as unreachable, which is the
        // honest answer for a socket that did not respond.
        return AgentList.read(status: run.status, output: run.output)
    }

    public func load(_ name: String) -> Bool { run(["-q"], on: name) }
    public func unload(_ name: String) -> Bool { run(["-d"], on: name) }

    private func run(_ arguments: [String], on name: String) -> Bool {
        guard !name.isEmpty, !name.contains("/"), name != "..", name != "." else { return false }
        let path = directory.appendingPathComponent(name).path
        return HelmProcess.run("/usr/bin/ssh-add", arguments + [path], timeout: deadline).status == 0
    }
}

/// `ssh-keygen`, on a terminal.
///
/// The whole body is the pty: no `-N`, so the tool asks the way it asks a
/// person, and `PTYProcess` answers and zeroes the buffer.
public struct SystemKeyGenerator: KeyGeneratorPort {
    private let deadline: TimeInterval
    /// Longer than the other two tools' bound, and deliberately: an RSA 4096
    /// key is seconds of work on an old Mac, where `ssh-add -l` is a socket
    /// round trip. A deadline that fits the fast tool would kill the slow one
    /// halfway through writing a key.
    public init(deadline: TimeInterval = 120) { self.deadline = deadline }

    public func generate(_ arguments: [String], answering secret: inout Data) -> Int32 {
        PTYProcess.run("/usr/bin/ssh-keygen", arguments,
                       answering: &secret, timeout: deadline).status
    }
}
