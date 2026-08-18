import Foundation
import HelmContract
import HelmRuntime

/// The hosts file, the SSH config and the keys in `~/.ssh`.
public final class HostsEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down.
    ///
    /// It reaches disk as the `module.hosts.*` keys of a store and as the
    /// module named in the log. `HostsDescriptor.id` is built from this rather
    /// than repeating it — the direction the descriptors already carry their
    /// command enums — so the two spellings are one.
    public static let moduleID = "hosts"

    private let file: HostsFilePort
    private let privileged: PrivilegedPort
    private let backups: BackupPort
    private let now: @Sendable () -> Date
    private let keptBackups: Int

    private let localTransport: LocalTransport
    public let transport: EngineTransport

    /// **Every port is named at every construction in tests.** A default
    /// argument naming a real port makes a forgetful test an integration test:
    /// eleven Autopilot tests took the Mac's own keychain that way and rolled
    /// the owner's real rules back.
    public init(file: HostsFilePort = SystemHostsFile(),
                privileged: PrivilegedPort = SystemPrivileged(),
                backups: BackupPort = SystemBackups(),
                now: @escaping @Sendable () -> Date = { Date() },
                keptBackups: Int = 10,
                transport: LocalTransport = LocalTransport()) {
        self.file = file
        self.privileged = privileged
        self.backups = backups
        self.now = now
        self.keptBackups = keptBackups
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {
        // The state goes out during activate, before any view model exists —
        // the transport replays it to whoever subscribes afterwards.
        emitState()
    }

    public func deactivate() {}

    // MARK: - Reading

    /// Reads the world, says what it found, and hands back the very value that
    /// went out.
    ///
    /// The reply to `load` is that value rather than a second reading: the file
    /// and the folder are two I/O round trips each time, and two readings can
    /// also *disagree* — `/etc/hosts` is a file any admin program may rewrite,
    /// so the page would be told one thing by its reply and another by the
    /// event it is subscribed to.
    @discardableResult
    private func emitState() -> HostsState {
        let text = file.read()
        let state = HostsState(hostsText: text ?? "", hostsReadable: text != nil,
                               backups: backups.list())
        localTransport.emit(HostsEvent.state, encoding: state)
        return state
    }

    private func emitOperation(_ operation: HostsOperation) {
        localTransport.emit(HostsEvent.operation, encoding: operation)
    }

    // MARK: - Writing

    /// Copy, ask root, read back and compare. **The order is the design.**
    ///
    /// A write with nothing to go back to is not attempted, so the copy comes
    /// first; a refusal that would take a copy anyway comes before it, because
    /// ten copies are kept and one taken for a write that never happens prunes
    /// the oldest real one; and a port that reports `done` over a file it did
    /// not change — or emptied — is believed by nothing but the read-back.
    func apply(_ text: String) async -> HostsOutcome {
        await HelmActivity.phase("hosts.apply") {
            emitOperation(HostsOperation(running: true))
            defer { emitState() }

            guard let current = file.read() else {
                HelmLog.shared.warn(Self.moduleID, "the hosts file could not be read; not writing")
                return finish(.failed)
            }

            // Asked before the encode, so a file too large to carry is told
            // apart from a payload the gate refused — and before the copy, so
            // that a refusal costs nobody one of the ten they are keeping.
            guard HostsWrite.fits(text) else {
                HelmLog.shared.warn(Self.moduleID, "the file is too large for the privileged write")
                return finish(.tooLarge)
            }
            guard backups.save(current, name: BackupName.name(at: now())) else {
                HelmLog.shared.warn(Self.moduleID, "no copy could be saved; not writing")
                return finish(.noBackup)
            }
            backups.delete(BackupName.pruned(backups.list(), keeping: keptBackups))

            guard let command = HostsWrite.command(base64: HostsWrite.encode(text)) else {
                HelmLog.shared.error(Self.moduleID, "the payload was refused by its own gate")
                return finish(.failed)
            }

            // osascript sits on the dialog for as long as the person takes,
            // which can be minutes. A pool thread must not be the one waiting.
            switch await offTheCooperativePool({ self.privileged.run(command) }) {
            case .declined:
                return finish(.declined)
            case .failed(let status):
                HelmLog.shared.warn(Self.moduleID, "the privileged write failed with \(status)")
                return finish(.failed)
            case .done:
                // The channel that says so — and a digest rather than a string
                // compare because **the log carries no names**. A hosts file is
                // nothing but names; its digest is the one form of it this app
                // may write down, and `.notVerified` is the outcome that most
                // needs something to look at afterwards.
                let intended = HexDigest.string(of: text.utf8)
                let written = file.read().map { HexDigest.string(of: $0.utf8) }
                guard written == intended else {
                    HelmLog.shared.error(Self.moduleID, "root reported success and the file on "
                                         + "disk differs: wrote \(written ?? "unreadable"), "
                                         + "meant \(intended)")
                    return finish(.notVerified)
                }
                return finish(.applied)
            }
        }
    }

    /// One place the verdict is written down and said out loud, so no arm can
    /// return an outcome the page never hears about.
    private func finish(_ outcome: HostsOutcome) -> HostsOutcome {
        HelmLog.shared.info(Self.moduleID, "apply: \(outcome.rawValue)")
        emitOperation(HostsOperation(running: false, lastOutcome: outcome.rawValue))
        return outcome
    }

    /// A backup id arrives over the wire, so it may only ever *select* a name
    /// the port already listed. It never builds a path, which is why
    /// `../../etc/sudoers` is answered with a refusal rather than a resolution.
    ///
    /// Two conditions and neither is the other's excuse: the membership is
    /// about *which* copy, and the read is about a folder that can lose a file
    /// between the listing and the restore. `SystemBackups` gates the name
    /// again on its own side, where the gate carries weight against a real
    /// neighbouring file.
    func restore(_ backupID: String) async -> HostsOutcome {
        guard backups.list().contains(backupID), let text = backups.read(backupID) else {
            HelmLog.shared.warn(Self.moduleID, "a restore named a copy that is not there")
            return .failed
        }
        return await apply(text)
    }

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            // A name this engine does not know is a refusal here, once, rather
            // than a `default` at the bottom of a switch nobody re-reads.
            guard let name = HostsCommand(rawValue: command.name) else { return Data() }
            switch name {
            case .load:
                return EngineReply.encode(self.emitState(), for: command)
            case .applyHosts:
                guard let request = EngineReply.decode(HostsApply.self, from: command)
                else { return Data() }
                return EngineReply.encode(await self.apply(request.text), for: command)
            case .restoreHosts:
                guard let request = EngineReply.decode(HostsRestore.self, from: command)
                else { return Data() }
                return EngineReply.encode(await self.restore(request.backupID), for: command)
            case .settingsChanged:
                self.emitState()
                return Data()
            }
        }
    }
}
