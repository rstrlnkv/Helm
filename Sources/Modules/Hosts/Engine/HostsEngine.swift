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

    private let sshConfig: SSHConfigPort
    private let knownHosts: KnownHostsPort
    private let keys: SSHKeysPort
    private let agent: SSHAgentPort
    private let generator: KeyGeneratorPort
    /// Whether a key is being made right now, and the lock that answers it.
    ///
    /// **A flag rather than a queue.** Two generations pointed at one path is
    /// how a key that was just made is replaced by another nobody asked for —
    /// and the second press is answered, not dropped, so the page can say why.
    private let generating = NSLock()
    private var makingKey = false
    /// The home directory the gate judges against — injected so a test can own
    /// a home of its own rather than the machine's.
    private let home: URL
    /// Where the reading `activate()` asks for runs, and the item it is, held so
    /// teardown can cancel one that has not begun. See `activate()`.
    private let readings = DispatchQueue(label: "helm.hosts.readings", qos: .userInitiated)
    private let firstReadingLock = NSLock()
    private var firstReading: DispatchWorkItem?
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    /// **Every port is named at every construction in tests.** A default
    /// argument naming a real port makes a forgetful test an integration test:
    /// eleven Autopilot tests took the Mac's own keychain that way and rolled
    /// the owner's real rules back.
    public init(file: HostsFilePort = SystemHostsFile(),
                privileged: PrivilegedPort = SystemPrivileged(),
                backups: BackupPort = SystemBackups(),
                sshConfig: SSHConfigPort = SystemSSHConfig(),
                knownHosts: KnownHostsPort = SystemKnownHosts(),
                keys: SSHKeysPort = SystemSSHKeys(),
                agent: SSHAgentPort = SystemSSHAgent(),
                generator: KeyGeneratorPort = SystemKeyGenerator(),
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                now: @escaping @Sendable () -> Date = { Date() },
                keptBackups: Int = 10,
                transport: LocalTransport = LocalTransport()) {
        self.file = file
        self.privileged = privileged
        self.backups = backups
        self.sshConfig = sshConfig
        self.knownHosts = knownHosts
        self.keys = keys
        self.agent = agent
        self.generator = generator
        self.home = home
        self.now = now
        self.keptBackups = keptBackups
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    /// **The thread that draws asks for the reading and does not wait for it.**
    ///
    /// `ModuleHost` is `@MainActor` and calls this from `enable(_:)` at every
    /// launch, so whatever happens here happens before the menu bar is drawn.
    /// `emitState()` is not a cheap call to make there: `ssh-add -l` is a round
    /// trip to a socket bounded at 5 s, and one `ssh-keygen -l` per key is
    /// bounded at 5 s each — deadlines that exist *because* both tools can sit,
    /// on a dead `SSH_AUTH_SOCK` or a stalled network mount. Every other
    /// engine's `activate()` is empty or a store read.
    ///
    /// The state still goes out, before any view model exists, and the
    /// transport replays it to whoever subscribes afterwards — so nothing is
    /// lost by the caller not waiting. The item is held rather than dropped:
    /// once the reading has begun it holds this engine for its own duration,
    /// and a reading that has not begun must not start after teardown.
    public func activate() {
        let reading = DispatchWorkItem { [weak self] in _ = self?.emitState() }
        firstReadingLock.withLock { firstReading = reading }
        readings.async(execute: reading)
    }

    public func deactivate() {
        firstReadingLock.withLock {
            firstReading?.cancel()
            firstReading = nil
        }
    }

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
        let ssh = sshConfig.read()
        let keyring = readKeys()
        let known = knownHosts.read()
        let state = HostsState(hostsText: text ?? "", hostsReadable: text != nil,
                               backups: backups.list(),
                               sshText: ssh ?? "", sshReadable: ssh != nil,
                               sshWritable: mayWriteSSH(),
                               keys: keyring.rows, keysReadable: keyring.readable,
                               directoryPermission: keyring.directory,
                               agent: keyring.agent,
                               knownHostsText: known ?? "", knownHostsReadable: known != nil,
                               knownHostsWritable: mayWriteKnownHosts(),
                               // The home this reading was taken under, so the
                               // page joins `IdentityFile` against the same
                               // directory the keys were listed from rather
                               // than asking its own process.
                               home: home.path)
        localTransport.emit(HostsEvent.state, encoding: state)
        return state
    }

    private func emitOperation(_ operation: HostsOperation) {
        localTransport.emit(HostsEvent.operation, encoding: operation)
    }

    // MARK: - The keys

    /// One reading of `~/.ssh`: what is in it, what the agent holds, and the
    /// directory's own verdict.
    ///
    /// **The agent is asked once per reading, not once per key.** `ssh-add -l`
    /// is a round trip to a socket and the answer is about all of them; asking
    /// it per row would also let two rows disagree about the same agent inside
    /// one snapshot.
    private func readKeys() -> (rows: [KeyRow], readable: Bool, directory: KeyRow.Permission,
                                agent: AgentList) {
        HelmActivity.phase("hosts.keys.read") {
            guard let names = keys.names() else {
                // Not there, or a directory this process may not search. Not an
                // empty directory, and the page says a different thing for each.
                return ([], false, .unknown, agent.list())
            }
            let held = agent.list()
            let rows = KeyInventory.pairs(in: names).map {
                KeyRow.row(from: keys.facts(for: $0), agent: held)
            }
            return (rows, true, directoryVerdict(), held)
        }
    }

    private func directoryVerdict() -> KeyRow.Permission {
        guard let mode = keys.directoryMode() else { return .unknown }
        switch KeyPermissions.directory(mode) {
        case .ok: return .ok
        case .tooOpen(let fix): return .tooOpen(fix: fix)
        }
    }

    /// A name from a payload may only ever *select* a key the engine can
    /// already see. It never becomes a path here — the port composes one, and
    /// refuses a name that is not a plain component on its own side.
    private func selected(_ name: String) -> KeyInventory.Pair? {
        guard let names = keys.names() else { return nil }
        return KeyInventory.pairs(in: names).first { $0.name == name }
    }

    /// `chmod` one key to the mode `ssh` accepts.
    ///
    /// A key already at an acceptable mode answers `done` and runs nothing: the
    /// button is idempotent, and a page one refresh out of date must not turn a
    /// no-op into a failure. A mode that could not be *read* is not fixed —
    /// writing a mode over a file this process could not stat is a guess, and
    /// the page keeps saying it does not know.
    func fixPermissions(of name: String) -> KeyOutcome {
        defer { emitState() }
        guard let pair = selected(name) else {
            HelmLog.shared.warn(Self.moduleID, "a permission fix named a key that is not there")
            return .notFound
        }
        switch KeyRow.row(from: keys.facts(for: pair), agent: .unreachable).permission {
        case .ok:
            return .done
        case .unknown:
            HelmLog.shared.warn(Self.moduleID, "the key's mode could not be read; not writing one")
            return .failed
        case .tooOpen(let fix):
            guard keys.chmod(name, to: fix) else {
                HelmLog.shared.warn(Self.moduleID, "the key's mode could not be changed")
                return .failed
            }
            return .done
        }
    }

    /// The same for `~/.ssh` itself, which has its own mode and its own fix.
    func fixDirectoryPermissions() -> KeyOutcome {
        defer { emitState() }
        switch directoryVerdict() {
        case .ok:
            return .done
        case .unknown:
            HelmLog.shared.warn(Self.moduleID, "the ssh directory's mode could not be read")
            return .failed
        case .tooOpen(let fix):
            guard keys.chmodDirectory(to: fix) else {
                HelmLog.shared.warn(Self.moduleID, "the ssh directory's mode could not be changed")
                return .failed
            }
            return .done
        }
    }

    /// Into the agent, or back out of it.
    ///
    /// **An unreachable agent is answered before anything is attempted.** A
    /// load against a dead socket fails in a way that reads like a problem with
    /// the key, and the key is fine — there is no agent. The page says so and
    /// offers nothing to press.
    ///
    /// A load runs on a terminal (`PTYProcess`), because `ssh-add` asks for a
    /// passphrase the way `ssh-keygen` does and has no flag that would take one
    /// safely. The secret arrives in a `Secret` — a reference to the one buffer
    /// the decode produced — is moved out of it into the `inout` argument, and
    /// the port zeroes it. **A `Data` parameter here was the defect**: the
    /// parameter stayed alive beside `var carried = passphrase`, so the buffer
    /// was never unique and `resetBytes` zeroed a copy.
    func load(_ name: String, passphrase: Secret) async -> KeyOutcome {
        defer { emitState() }
        guard selected(name) != nil else {
            HelmLog.shared.warn(Self.moduleID, "an agent act named a key that is not there")
            return .notFound
        }
        guard agent.list() != .unreachable else {
            HelmLog.shared.info(Self.moduleID, "there is no agent to load a key into")
            return .agentUnreachable
        }
        // `ssh-add` sits on its prompt for as long as somebody would take to
        // type, and the pty read blocks for all of it. A pool thread must not
        // be the one waiting — the rule `apply` follows for the password dialog.
        let outcome = await offTheCooperativePool { [agent] in
            // `take()` and not a copy: what goes in is the buffer the JSON
            // decode produced, and nothing else refers to it by the time the
            // port zeroes it.
            var carried = passphrase.take()
            defer { carried = Data() }
            return agent.load(name, answering: &carried)
        }
        switch outcome {
        case .loaded:
            return .done
        case .needsPassphrase:
            // Not a failure, and the log says so in those words: a locked key is
            // a key doing exactly what a passphrase is for.
            HelmLog.shared.info(Self.moduleID, "the agent asked for a passphrase")
            return .needsPassphrase
        case .failed:
            HelmLog.shared.info(Self.moduleID, "the agent refused the key")
            return .failed
        }
    }

    /// Out of the agent. No terminal and no secret: taking a key out is not a
    /// question anybody is asked.
    func unload(_ name: String) -> KeyOutcome {
        defer { emitState() }
        guard selected(name) != nil else {
            HelmLog.shared.warn(Self.moduleID, "an agent act named a key that is not there")
            return .notFound
        }
        guard agent.list() != .unreachable else { return .agentUnreachable }
        return agent.unload(name) ? .done : .failed
    }

    /// Make a key.
    ///
    /// Every refusal is decided before a child exists, and the one that matters
    /// most is `nameTaken`: `ssh-keygen` asks before it overwrites, and an
    /// answer given to a question the person never saw is how a key is
    /// destroyed. So Helm never points it at a name that is already there.
    ///
    /// **The secret travels in a `Secret` and is moved, never copied**, so the
    /// buffer the port zeroes is the buffer the person's passphrase was decoded
    /// into and nothing else refers to it. This used to be `let secret =
    /// request.passphrase` with the request alive beside it, which is two
    /// references to a copy-on-write buffer — so `resetBytes` allocated, zeroed
    /// the allocation, and left the passphrase where it was. The request itself
    /// is not logged — the log carries no names, and a comment is somebody's
    /// address.
    func generate(_ request: KeyGeneration.Request, secret: Secret) async -> GenerateOutcome {
        guard claimGeneration() else { return .alreadyRunning }
        defer { releaseGeneration(); emitState() }

        guard KeyGeneration.isPlain(request.name),
              let names = keys.names(), !names.contains(request.name),
              !names.contains(request.name + ".pub") else {
            let refusal: KeyGeneration.Refusal =
                KeyGeneration.isPlain(request.name) ? .nameTaken : .notAPlainName
            HelmLog.shared.warn(Self.moduleID, "a key was not made: \(refusal.rawValue)")
            return GenerateOutcome.of(refusal)
        }

        switch KeyGeneration.arguments(for: request, in: keys.directory) {
        case .failure(let refusal):
            HelmLog.shared.warn(Self.moduleID, "a key was not made: \(refusal.rawValue)")
            return GenerateOutcome.of(refusal)
        case .success(let arguments):
            // **Nothing is emitted on `HostsEvent.operation` here.** That event
            // is `/etc/hosts`'s, and a generation spoke on it: `running` is
            // what disables Apply and draws the unsaved bar, and the outcome
            // arrived as the hosts file's own word because the two enums spell
            // `failed` alike. The page learns how a generation went from this
            // call's reply, which is where `HostsViewModel.generated` already
            // takes it from, and that it is running from its own `makingKey` —
            // a generation is started by the page, so no other reader has to be
            // told about it.
            //
            // `ssh-keygen` on an RSA 4096 key is seconds of work and the pty
            // read blocks for all of them. A pool thread must not be the one
            // waiting — the rule `apply` follows for the password dialog.
            let status = await offTheCooperativePool { [generator] in
                var carried = secret.take()
                defer { carried = Data() }
                return generator.generate(arguments, answering: &carried)
            }
            let outcome: GenerateOutcome = status == 0 ? .done : .failed
            HelmLog.shared.info(Self.moduleID, "generate: \(outcome.rawValue)")
            return outcome
        }
    }

    private func claimGeneration() -> Bool {
        generating.lock(); defer { generating.unlock() }
        guard !makingKey else { return false }
        makingKey = true
        return true
    }

    private func releaseGeneration() {
        generating.lock(); defer { generating.unlock() }
        makingKey = false
    }

    // MARK: - The config in the person's own home

    /// Whether the gate would let a write through, asked wherever the page or
    /// the write itself needs to know — one reader, so the button and the
    /// refusal cannot come to different conclusions.
    private func mayWriteSSH() -> Bool {
        SSHFileScope.mayWrite(sshConfig.url, home: home,
                              under: home.appendingPathComponent(".ssh"))
    }

    private func mayWriteKnownHosts() -> Bool {
        SSHFileScope.mayWrite(knownHosts.url, home: home,
                              under: home.appendingPathComponent(".ssh"))
    }

    /// The same three steps as the config next door: gate, write, read back.
    ///
    /// **The whole file crosses the wire, exactly as `applySSHConfig` does**,
    /// and in this file that only ever means «with one line gone». An index
    /// would be a second contract about which line, decided on one side of the
    /// wire and acted on at the other after the file may have changed — and the
    /// thing being removed is somebody's record of a host they trust.
    /// Gate, **read the file again**, drop the line, write, read back.
    ///
    /// The reading the page acts from is minutes old by the time somebody
    /// presses Forget, and `known_hosts` is the one file here that grows under
    /// the app: `ssh` appends a line to it from any terminal the moment a new
    /// machine is trusted. Rendering the whole document from the page's
    /// snapshot wrote every one of those away, and the read-back could not
    /// see it — it compares what was sent with what was written, and those two
    /// agree exactly. So the act names a line and the removal happens against
    /// the file as it is now.
    ///
    /// A line no longer there is `.applied` with nothing written: what Forget
    /// asked for — that this host is not trusted — already holds, and a failure
    /// over it would be a false alarm on a second press. `testForgetting…`
    /// asserts the write count on the ordinary case, so an implementation that
    /// matched nothing ever would fail rather than report success everywhere.
    private func forgetKnownHost(_ line: String) -> SSHConfigOutcome {
        HelmActivity.phase("hosts.knownHosts.forget") {
            defer { emitState() }
            guard mayWriteKnownHosts() else {
                HelmLog.shared.warn(Self.moduleID,
                                    "the known_hosts path is outside what may be written")
                return .outOfScope
            }
            guard let current = knownHosts.read() else {
                HelmLog.shared.warn(Self.moduleID, "known_hosts could not be read to forget from")
                return .failed
            }
            let text = KnownHostsFile.render(
                KnownHostsFile.forget(line: line, in: KnownHostsFile.parse(current)))
            guard text != current else {
                HelmLog.shared.info(Self.moduleID, "the host to forget is already not trusted")
                return .applied
            }
            guard knownHosts.write(text) else {
                HelmLog.shared.warn(Self.moduleID, "known_hosts could not be written")
                return .failed
            }
            guard knownHosts.read() == text else {
                HelmLog.shared.error(Self.moduleID,
                                     "the write reported success and the file is not what was sent")
                return .notVerified
            }
            return .applied
        }
    }

    /// Gate, write, read back, compare.
    ///
    /// **The read-back is not ceremony.** A write that returns success over a
    /// file that did not change is exactly the shape the privileged path was
    /// caught in, and it is reachable here too — a full disk, a file replaced
    /// under the app between the gate and the write, a port that answers for a
    /// path it did not touch. Reporting success is a claim; the file is the
    /// evidence.
    ///
    /// No backup and no dialog: the file is the person's own, and this is the
    /// difference tab 2 has from tab 1 all the way down.
    private func applySSH(_ text: String) -> SSHConfigOutcome {
        HelmActivity.phase("hosts.ssh.apply") {
            defer { emitState() }
            guard mayWriteSSH() else {
                HelmLog.shared.warn(Self.moduleID,
                                    "the ssh config path is outside what may be written")
                return .outOfScope
            }
            guard sshConfig.write(text) else {
                HelmLog.shared.warn(Self.moduleID, "the ssh config could not be written")
                return .failed
            }
            guard sshConfig.read() == text else {
                HelmLog.shared.error(Self.moduleID,
                                     "the write reported success and the file is not what was sent")
                return .notVerified
            }
            return .applied
        }
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
        emitOperation(HostsOperation(running: false, lastOutcome: outcome))
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
            case .applySSHConfig:
                guard let request = EngineReply.decode(SSHConfigApply.self, from: command)
                else { return Data() }
                return EngineReply.encode(self.applySSH(request.text), for: command)
            case .forgetKnownHost:
                guard let request = EngineReply.decode(KnownHostsForget.self, from: command)
                else { return Data() }
                return EngineReply.encode(self.forgetKnownHost(request.line), for: command)
            case .fixKeyPermissions:
                guard let request = EngineReply.decode(KeyName.self, from: command)
                else { return Data() }
                return EngineReply.encode(self.fixPermissions(of: request.name), for: command)
            case .fixDirectoryPermissions:
                return EngineReply.encode(self.fixDirectoryPermissions(), for: command)
            case .agentLoad:
                // The bytes come out of the decoded payload here, at the one
                // place they arrive, and the payload keeps none: a passphrase
                // left in two places cannot be zeroed in either. See `Secret`.
                guard var request = EngineReply.decode(KeyLoad.self, from: command)
                else { return Data() }
                let given = Secret(taking: &request.passphrase)
                return EngineReply.encode(
                    await self.load(request.name, passphrase: given), for: command)
            case .agentUnload:
                guard let request = EngineReply.decode(KeyName.self, from: command)
                else { return Data() }
                return EngineReply.encode(self.unload(request.name), for: command)
            case .generateKey:
                guard var request = EngineReply.decode(KeyGeneration.Request.self, from: command)
                else { return Data() }
                let typed = Secret(taking: &request.passphrase)
                return EngineReply.encode(await self.generate(request, secret: typed),
                                          for: command)
            case .agentRefresh:
                return EngineReply.encode(self.emitState(), for: command)
            case .settingsChanged:
                self.emitState()
                return Data()
            }
        }
    }
}
