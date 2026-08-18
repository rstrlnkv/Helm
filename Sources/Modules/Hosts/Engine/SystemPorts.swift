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
