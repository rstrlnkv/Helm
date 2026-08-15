// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime

/// Orchestrates VPN connect/disconnect/toggle (via `scutil --nc`) and per-app
/// auto-connect (VPNAutoConnectCore) against the injected ports. `activate()`/
/// `deactivate()` are the MODULE lifecycle (host enables/disables the module);
/// they also start/stop the auto-connect app observation.
/// Where the engine does work that blocks.
///
/// `scutil` is a subprocess: on this machine a single `--nc list` measured
/// 16 ms, and a connect polls it up to 25 times. All of that used to run on the
/// main thread — through `DispatchQueue.main.asyncAfter` for the poll, and
/// through AppKit's own running-applications notification for auto-connect,
/// which also reaches a synchronous keychain read that can put a modal panel on
/// screen. Tests drive the engine synchronously and assert on the commands it
/// issued, so they run it `.inline`; the app runs it `.background`.
public enum VPNWorkQueue: Sendable {
    case background
    case inline

    fileprivate func run(_ block: @escaping @Sendable () -> Void) {
        switch self {
        case .inline: block()
        case .background: Self.queue.async(execute: block)
        }
    }

    fileprivate func run(after seconds: Double, _ block: @escaping @Sendable () -> Void) {
        switch self {
        case .inline: block()
        case .background: Self.queue.asyncAfter(deadline: .now() + seconds, execute: block)
        }
    }

    /// Serial: the engine's state is guarded by a lock, but the commands it
    /// sends to `scutil` still have to arrive in the order they were asked for.
    private static let queue = DispatchQueue(label: "helm.vpn", qos: .userInitiated)
}

public final class VPNEngine: ModuleEngine, @unchecked Sendable {
    private let settings: VPNSettings
    private let runner: VPNRunnerPort
    private let credentials: VPNCredentialsPort?
    private let apps: AppObserverPort
    private let network: NetworkWatchPort?
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    /// Written from the work queue and read from the UI, hence the lock — the
    /// class was `@unchecked Sendable` with no synchronisation at all, and an
    /// array written from two threads is not a race you get a warning for.
    private let lock = NSLock()
    private var _connections: [VPNConnection] = []
    private var _autoConnected: Set<String> = []
    /// The last command this module sent that the tool did not accept, cleared
    /// by the next one it did. One at a time on purpose: a page listing every
    /// refusal it has ever seen is a log, and there is one of those.
    private var _lastFailure: VPNFailure?
    /// Which of those were ever observed up — **the configuration's own id**,
    /// against the name Helm raised it under.
    ///
    /// Without it, "not up right now" cannot be told from "not up yet". Keyed by
    /// id because the name identifies nothing: macOS lets two service
    /// configurations carry one display name, and as a set of names this book
    /// answered "is one of them up", so a tunnel a rule was holding could fall
    /// over while a namesake happened to be up and the drop was never reported —
    /// the one event this module posts a system notification for. The name is
    /// kept beside the id because a configuration deleted between two reads is
    /// gone from the list, and the drop still has to be named.
    ///
    /// `_autoConnected` stays a set of **names**, and that is not an oversight:
    /// `--nc start`/`--nc stop` take a name, so what the quit rule owns has to be
    /// something it can take down. Which is also why the ambiguity is
    /// irreducible rather than merely unfixed here — Helm asks for a name, macOS
    /// picks the configuration.
    private var _cameUp: [String: String] = [:]
    /// Which configurations Helm has no usable secret for — `VPNSecretBook`, under
    /// the same lock as the two books above it, and for the same reason: written
    /// from the work queue, read by the page.
    private var _secrets = VPNSecretBook()
    private var _lastAutomation: VPNAutomation?

    public var lastAutomation: VPNAutomation? {
        lock.lock(); defer { lock.unlock() }; return _lastAutomation
    }

    /// Test seam: lets a test tell "nothing was written here" from "nothing was
    /// ever written". Nothing in the app clears this.
    func clearLastAutomationForTesting() {
        lock.lock(); _lastAutomation = nil; lock.unlock()
    }

    public var lastFailure: VPNFailure? {
        lock.lock(); defer { lock.unlock() }
        return _lastFailure
    }

    /// The configurations a rule cannot raise, because their secret is in the
    /// System keychain and only a person's own gesture may open it.
    ///
    /// On the wire and drawn, not merely logged: the two changes that produced
    /// this state — the one-time purge of the old credential cache and the refusal
    /// to prompt for an automatic connect — are both correct, and together they
    /// left a rule reaching the same dead end at every launch of its app with
    /// nothing but `~/Library/Logs/Helm/helm.log` to say so.
    public var secretsBehindAPrompt: [String] {
        lock.lock(); defer { lock.unlock() }; return _secrets.names
    }

    public var connections: [VPNConnection] {
        lock.lock(); defer { lock.unlock() }; return _connections
    }
    public var autoConnected: Set<String> {
        lock.lock(); defer { lock.unlock() }; return _autoConnected
    }

    private var core = VPNAutoConnectCore(rules: [:])
    private var knownBundleIDs: Set<String> = []
    /// Under the lock, like the four above it and unlike the rest of this
    /// group.
    ///
    /// `core` and `knownBundleIDs` are touched only from the work queue, which
    /// is serial, so they need nothing. This one is written by `activate()` and
    /// `deactivate()` on the host's thread and read by `appsChangedNow()` on the
    /// work queue — the two-thread case the lock at the top of this class exists
    /// for, and the comment there says why a bare property is not a race anyone
    /// gets a warning for. It was the one field of that group that crossed.
    private var _running = false
    private var running: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _running }
        set { lock.lock(); _running = newValue; lock.unlock() }
    }
    private let work: VPNWorkQueue
    /// Injected so a firing's moment is a fact of the caller rather than of the
    /// machine — `VPNAutomation.spinPhase` measures from it.
    private let now: @Sendable () -> Date

    public init(settings: VPNSettings,
                runner: VPNRunnerPort,
                credentials: VPNCredentialsPort? = nil,
                apps: AppObserverPort,
                network: NetworkWatchPort? = nil,
                transport: LocalTransport = LocalTransport(),
                now: @escaping @Sendable () -> Date = Date.init,
                work: VPNWorkQueue = .background) {
        self.now = now
        self.work = work
        self.settings = settings
        self.runner = runner
        self.credentials = credentials
        self.apps = apps
        self.network = network
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    // MARK: - ModuleEngine (module enabled/disabled)

    public func activate() {
        running = true
        // Read where reading is safe: `RunningApps` answers live only on the
        // main thread, and this runs from `ModuleHost.enable`.
        let launched = apps.runningBundleIDs()
        // Everything that touches `core` goes on the one serial queue that
        // owns it. Seeding used to run on the caller's thread while the
        // just-enqueued reload wrote `core.rules` on the work queue, with
        // nothing synchronising the two — the same shape as the crash that
        // `RunningApps` was written for.
        //
        // Off the main thread also because this shells out to scutil at
        // launch, before the window is on screen.
        work.run { [weak self] in
            guard let self else { return }
            self.reloadRulesNow()
            self.knownBundleIDs = launched
            for id in launched { self.launchIfTrusted(id) }
        }
        apps.startObserving { [weak self] in self?.appsChanged() }
        // The one question this module answers is asked of the system, not of a
        // cache: a tunnel raised from the menu bar, stopped in System Settings
        // or dropped by the network never comes back through Helm.
        network?.startObserving { [weak self] in
            // An observer that never fires and an observer that fires and finds
            // nothing changed look identical from outside the process, and the
            // release process triages dev builds against the log. One line per
            // real network event, no names in it.
            HelmLog.shared.info("vpn", "network state changed; re-reading")
            self?.refresh()
        }
    }

    public func deactivate() {
        running = false
        network?.stopObserving()
    }

    /// The backstop for the routes that do not go through `deactivate()`.
    /// ARCHITECTURE.md § "An observer outlives the thing it points at".
    deinit { network?.stopObserving() }

    // MARK: - VPN control

    public func refresh() {
        work.run { [weak self] in self?.refreshNow() }
    }

    /// The blocking half, always on the work queue.
    private func refreshNow() {
        let output = runner.run(["--nc", "list"]).output
        // Silence is not an answer. `scutil`'s exit status never reaches us, so
        // a read that failed looks exactly like a Mac with no VPNs — and acting
        // on it does two kinds of damage: the page announces that the user's
        // connections are gone while they are up, and the drop detection below,
        // which asks what is missing from this list, decides that everything
        // Helm ever raised fell over at once. Keeping the last real answer is
        // the only honest response to not being told anything.
        guard VPNListParser.isReadable(output) else {
            HelmLog.shared.warn("vpn", "connection list unreadable; keeping the last answer")
            return
        }
        let parsed = VPNListParser.parseList(output)
        lock.lock()
        _connections = parsed
        // A VPN Helm raised can also drop on its own — the network goes, the
        // server hangs up, somebody stops it in System Settings. The set was
        // only ever emptied by Helm disconnecting it, so the strip went on
        // saying "AUTOMATIC 1" beside "ACTIVE 0" until the app restarted.
        //
        // "Not up" is not enough to forget it by: the refresh that follows a
        // connect usually still reports the old status, so intersecting with
        // what is up would wipe a connection Helm had just raised, before it
        // had a chance to come up. What is forgotten is one that *came* up and
        // then went — which needs remembering that it ever did.
        //
        // All of it asked of ids rather than names: what fell over is a
        // *configuration*, and two of them can share a name.
        let up = Set(parsed.filter(\.status.isUp).map(\.id))
        // The fall is read before anything new is adopted, so a namesake that
        // came up for its own reasons in the same breath is not mistaken for the
        // tunnel that went. Helm cannot tell which configuration `--nc start`
        // acted on; it can tell that the one it watched come up is down.
        let fallen = _cameUp.filter { !up.contains($0.key) }
        for id in fallen.keys { _cameUp[id] = nil }
        // A name is only forgotten when nothing Helm watched come up still
        // carries it — the same rule as the report below, so the page's book and
        // the news agree.
        let dropped = Set(fallen.values).subtracting(_cameUp.values)
        _autoConnected.subtract(dropped)
        for connection in parsed where connection.status.isUp
            && _autoConnected.contains(connection.name) {
            _cameUp[connection.id] = connection.name
        }
        // The reverse channel for the secret book: a tunnel that is up needed
        // nothing from Helm after all, and a configuration deleted in System
        // Settings is nothing to draw a sentence about. Without this the notice
        // would be a warning nobody can clear.
        _secrets.reconcile(against: parsed)
        lock.unlock()
        // Recorded outside the lock the names were collected under: sorted so
        // that when several go at once the last one written is the same on
        // every run.
        for name in dropped.sorted() {
            HelmLog.shared.info("vpn", "automatic connection dropped: \(Redact.vpn(name))")
            // `.dropped`, not `.disconnected`. Nobody asked for this one: the
            // network went, the server hung up, or somebody stopped it in
            // System Settings — and the person is now sending everything in
            // clear having last been told they were behind a tunnel. It is the
            // one firing here that can be set to arrive as a banner while the
            // rules stay quiet.
            recordAutomation(name, .dropped)
        }
        emitState()
    }

    public var defaultConnection: VPNConnection? {
        if let live = connections.first(where: \.status.isUp) {
            return live
        }
        return VPNListParser.defaultConnection(from: connections, lastUsedName: settings.lastUsedName)
    }

    public func toggleDefault() {
        work.run { [weak self] in self?.toggleDefaultNow() }
    }

    private func toggleDefaultNow() {
        refreshNow()
        guard let target = defaultConnection else { return }
        settings.setLastUsed(target.name)
        if target.status.isUp {
            disconnect(target.name)
        } else {
            connect(target.name)
        }
    }

    public func connect(_ name: String, auto: Bool = false) {
        work.run { [weak self] in self?.connectNow(name, auto: auto) }
    }

    private func connectNow(_ name: String, auto: Bool) {
        HelmLog.shared.info("vpn", "connect \(Redact.vpn(name))\(auto ? " (auto)" : "")")
        // Read before anything is asked of the tool, so this is what was true
        // when the rule asked rather than what Helm has since written down.
        let alreadyUp = auto ? status(name).isUp : false
        var args = ["--nc", "start", name]
        // **Known limitation, and the window is not small.** `scutil` takes the
        // shared secret, the password and the user name only as arguments, and
        // an argument list is readable by every process running as this user for
        // as long as the process lives. That used to be written down here as "a
        // fraction of a second, but not zero", which understates it by an order
        // of magnitude. Measured with an unprivileged same-user sweeper against
        // a child of a known lifetime:
        //
        // | child lifetime | caught out of 25 |
        // |---|---|
        // | 16 ms | 24 |
        //
        // and 16 ms is this repository's own measured figure for one
        // `scutil --nc` call. So the honest sentence is: any process running as
        // this user that is looking will get the shared secret, the password and
        // the user name. There is no stdin form — `nc` is not a command
        // `scutil`'s interactive mode accepts — so closing this means driving
        // `NEVPNManager`/`NEConfiguration` instead of the tool, which needs a
        // Developer ID and is a rewrite of this path rather than a patch.
        //
        // What is cheap is not opening the window when nothing needs doing, which
        // is the `!alreadyUp` below: `--nc start` on a tunnel that is up is a
        // no-op, and `activate()` replays `appLaunched` for every app already
        // running, so a rule whose app runs all day published the secret at every
        // launch of Helm for a command that changed nothing.
        //
        // `promptingAllowed: !auto` is the other half, and it is about a
        // different exposure — see `VPNCredentialsPort`.
        // A tunnel that is already up needs nothing supplied and nothing said, so
        // it answers the same as a configuration that keeps no secret — and the
        // credential read is not performed at all.
        let step = alreadyUp ? VPNSecretBook.Step.nothingToSupply
                             : secretStep(for: name, auto: auto)
        switch step {
        case .supply(let creds):
            args += Self.arguments(for: creds)
        // Nothing goes on the command line either way. What separates the two is
        // whether a connection may be *announced* afterwards — read off `step`
        // below, where the announcement is.
        case .nothingToSupply, .tryWithoutIt:
            break
        case .refuse:
            HelmLog.shared.info("vpn", "no usable secret for \(Redact.vpn(name)) and a "
                + "rule may not ask for one; not attempted")
            // The one publication point, on the early return as well: a path that
            // skips it leaves the screen holding whatever it had.
            emitState()
            return
        }
        let reply = VPNCommandReply.of(runner.run(args), name: name, knownNames: knownNames)
        report(reply, verb: .connect, name: name)
        // **Announced after the tool answered, and only what it did.** This
        // block used to run *before* `scutil`, so a rule pointing at a
        // configuration renamed in System Settings lit the ring, put the name
        // in the menu bar and posted a banner saying «Connected to Old office»
        // with no tunnel behind any of it — the person then sends everything in
        // clear believing they are behind one, which is the harm
        // `VPNAutomation.Kind.dropped` exists to warn about, manufactured by
        // the app itself. One emitted payload carried `.connected` and
        // `.noSuchService` at once.
        //
        // Owning it and announcing it are still different questions — the quit
        // rule reads `_autoConnected`, so a tunnel already up is Helm's to take
        // down when the app goes — but neither may be claimed for a command the
        // tool refused.
        if auto, reply == .accepted {
            lock.lock(); _autoConnected.insert(name); lock.unlock()
            // Only when Helm actually changed something: `--nc start` on a
            // tunnel that is up is a no-op, and `activate()` replays
            // `appLaunched` for every app already running, so a rule whose app
            // runs all day fired this at every launch of Helm. Measured in the
            // menu bar rather than reasoned about — the ring spun 0.8 s after
            // each launch.
            //
            // **And never for a start Helm knowingly under-supplied.** `--nc start`
            // answers nothing whether it worked or not, so a connect whose secret
            // was behind a prompt lit the ring and put the name in the menu bar
            // while the page said the rule could not fire: one screen telling the
            // person they are behind a tunnel and another that they are not. Helm
            // owns the tunnel either way — the quit rule has to be able to take
            // down whatever came up — which is why only the announcement is held
            // back and `_autoConnected` is not.
            if !alreadyUp, step != .tryWithoutIt { recordAutomation(name, .connected) }
        }
        emitState()
        if reply == .accepted { poll(name, following: .connect) }
    }

    public func disconnect(_ name: String, auto: Bool = false) {
        work.run { [weak self] in self?.disconnectNow(name, auto: auto) }
    }

    private func disconnectNow(_ name: String, auto: Bool) {
        HelmLog.shared.info("vpn", "disconnect \(Redact.vpn(name))\(auto ? " (auto)" : "")")
        // Read before the books are touched, and mirror the connect side: a
        // teardown of a tunnel that is already down changes nothing, so
        // `scutil --nc stop` is a no-op and there is nothing to announce.
        // Announcing it anyway would name a disconnection the user never had,
        // which is the same lie as announcing one that never happened.
        let wasUp = status(name).isUp
        let reply = VPNCommandReply.of(runner.run(["--nc", "stop", name]), name: name,
                                       knownNames: knownNames)
        report(reply, verb: .disconnect, name: name)
        // Same rule as the connect side, and the same harm read backwards: this
        // used to record `.disconnected` and clear both books *before* the stop
        // ran, so a teardown the tool refused left the tunnel up, Helm no longer
        // owning it, and its eventual real drop unreportable — the module had
        // forgotten the one tunnel it was responsible for.
        //
        // Both books, when the tool did stop it. `_cameUp` is the memory of
        // "this one did come up", and a name left in it outlives the session it
        // belonged to: the next time the same app launches and Helm raises the
        // same VPN, the first refresh — the one that exists precisely because it
        // still reports the old status — sees a name that is not up and *was*
        // once up, and forgets it immediately. Connect and disconnect are this
        // module's ordinary traffic, so that is the common path, not an edge.
        if reply == .accepted {
            lock.lock()
            _autoConnected.remove(name)
            // By the name it was raised under, since the book is keyed by the
            // configuration's id now: `--nc stop` names a name, so everything
            // Helm was watching under that name is what this took down.
            _cameUp = _cameUp.filter { $0.value != name }
            lock.unlock()
            if auto, wasUp { recordAutomation(name, .disconnected) }
        }
        emitState()
        if reply == .accepted { poll(name, following: .disconnect) }
    }

    /// The tool's own spelling of a credential. Empty fields are left off rather
    /// than passed empty: `scutil` takes each of these as an argument, and an
    /// argument list is readable by every process running as this user (see the
    /// note in `connectNow`), so nothing goes on it that does not have to.
    private static func arguments(for creds: VPNCredentials) -> [String] {
        var arguments: [String] = []
        if let user = creds.user, !user.isEmpty { arguments += ["--user", user] }
        if let password = creds.password, !password.isEmpty {
            arguments += ["--password", password]
        }
        if let secret = creds.secret, !secret.isEmpty { arguments += ["--secret", secret] }
        return arguments
    }

    /// What a connect does about the secret this configuration needs, and the
    /// book's record of it — one step, under the lock the books share.
    ///
    /// **The third question the port used to fold away.** It answered
    /// `VPNCredentials?`, so «this configuration keeps no secret» (IKEv2) and
    /// «there is one and I may not read it» were one nil — and the engine could
    /// report neither: a rule met the second every time its app launched, ran a
    /// `--nc start` that could not work, announced a connection nobody had, and
    /// said so nowhere but the log. The rule about what to do with each answer is
    /// `VPNSecretBook.step`, where it is pure and tested.
    private func secretStep(for name: String, auto: Bool) -> VPNSecretBook.Step {
        let read = credentials?.credentials(for: name, promptingAllowed: !auto) ?? .notNeeded
        lock.lock(); defer { lock.unlock() }
        return _secrets.step(for: read, name: name, automatic: auto)
    }

    /// The one writer, so "Helm caused this" is decided in a single place. Under
    /// the same lock as `_autoConnected`, because `connectNow` runs on the work
    /// queue and the drop above runs on the refresh path.
    private func recordAutomation(_ name: String, _ kind: VPNAutomation.Kind) {
        let firing = VPNAutomation(at: now(), name: name, kind: kind)
        lock.lock(); _lastAutomation = firing; lock.unlock()
    }

    public func status(_ name: String) -> VPNStatus {
        connections.first(where: { $0.name == name })?.status ?? .unknown
    }

    /// Every configuration this Mac has, for the redaction of what the tool says
    /// about one of them. `scutil` explains a refusal by naming whichever
    /// configuration is in the way, not the one it was asked about, and the log
    /// carries no names.
    private var knownNames: [String] { connections.map(\.name) }

    /// Whether the command a poll is following has arrived: the connection it
    /// was about has reached the state the verb asked for.
    ///
    /// **Not «is anything transitioning», which is what this used to ask.**
    /// `refreshNow`'s own comment says the refresh after a connect «usually
    /// still reports the old status», and `Disconnected` is not a transition —
    /// so the poll read that first answer, found nothing moving, and stopped
    /// after one attempt. The 25 attempts that `maxPollAttempts` says cover a
    /// slow IKEv2 handshake were never spent on one, because a slow handshake is
    /// precisely the case that reads `Disconnected` first: the card then sat on
    /// «Disconnected» after a connect that worked, which is the wrong answer the
    /// network watcher was added to fix, in the same place.
    ///
    /// Asked of every namesake rather than of one row, like `status(_:)` above:
    /// Helm asks for a name and macOS picks the configuration, so «a
    /// configuration of that name has arrived» is as much as the tool's own
    /// vocabulary can say.
    static func settled(_ connections: [VPNConnection],
                        into wanted: VPNStatus, for name: String) -> Bool {
        connections.contains { $0.name == name && $0.status == wanted }
    }

    private var pollAttempts = 0
    private let maxPollAttempts = 25   // ~17s at 0.7s — covers slow IKEv2 handshakes

    /// A single 0.6s re-read used to leave the spinner stuck when the real
    /// handshake outlived it; keep polling until the command has arrived.
    ///
    /// **Only a command the tool accepted is followed**, which is the other half
    /// of asking for an outcome instead of for movement: waiting for a name
    /// `scutil` has already answered `No service` about would spend all 25
    /// attempts and 17 s of subprocesses on a tunnel that was never asked to
    /// come up. A refusal changed nothing, so there is nothing to re-read.
    ///
    /// And the ceiling is what stands under the other unresolvable case — a
    /// handshake that fails silently ends at `Disconnected`, which is
    /// indistinguishable from a tool that has not caught up yet. Tests use a
    /// synchronous runner and a scripted list, so the length of a poll is a
    /// number they can read.
    private func poll(_ name: String, following verb: VPNVerb) {
        pollAttempts = 0
        pollUntilSettled(name, verb.settledStatus)
    }

    private func pollUntilSettled(_ name: String, _ wanted: VPNStatus) {
        work.run(after: 0.7) { [weak self] in
            guard let self else { return }
            self.refreshNow()
            let trail = self.connections.map { "\(Redact.vpn($0.name))=\($0.status)" }
                .joined(separator: ", ")
            if Self.settled(self.connections, into: wanted, for: name) {
                HelmLog.shared.info("vpn", "settled: " + trail)
            } else if self.pollAttempts < self.maxPollAttempts {
                self.pollAttempts += 1
                self.pollUntilSettled(name, wanted)
            } else {
                HelmLog.shared.warn("vpn", "\(Redact.vpn(name)) never reached \(wanted) after "
                    + "\(self.pollAttempts) polls: " + trail)
            }
        }
    }

    /// What the tool said, in the trail and on the wire.
    ///
    /// Both call sites discarded it. `scutil` exits 0 whatever happens and puts
    /// its complaint on stdout, so a rule pointing at a configuration that was
    /// renamed in System Settings failed in silence — the tunnel never came up
    /// and nothing anywhere said why.
    ///
    /// The name is redacted in the log, like every other line this module
    /// writes; `_lastFailure` carries it unredacted because the screen is
    /// allowed to name what the person configured, and the log is not.
    /// The verb is the module's own enum rather than the word each call site
    /// used to hand this: `VPNFailure` carries it to the screen now, and a
    /// sentence naming the wrong verb is what this repair was about — a refused
    /// *stop* told the person the tunnel was down while it was up. One
    /// declaration, so the log word and the sentence cannot drift apart.
    private func report(_ reply: VPNCommandReply, verb: VPNVerb, name: String) {
        switch reply {
        case .accepted:
            lock.lock(); _lastFailure = nil; lock.unlock()
        case .noSuchService:
            HelmLog.shared.warn("vpn", "\(verb.rawValue) \(Redact.vpn(name)): "
                + "no such configuration")
            lock.lock()
            _lastFailure = VPNFailure(name: name, reason: .noSuchService, verb: verb)
            lock.unlock()
        case .refused(let text):
            HelmLog.shared.warn("vpn", "\(verb.rawValue) \(Redact.vpn(name)) refused: \(text)")
            lock.lock()
            _lastFailure = VPNFailure(name: name, reason: .refused, verb: verb)
            lock.unlock()
        }
    }

    // MARK: - Auto-connect

    public func reloadRules() {
        work.run { [weak self] in self?.reloadRulesNow() }
    }

    private func reloadRulesNow() {
        refreshNow()
        core.rules = VPNRules.valid(VPNRules.decode(settings.rulesJSON), against: connections)
    }

    private func appsChanged() {
        work.run { [weak self] in self?.appsChangedNow() }
    }

    private func appsChangedNow() {
        guard running else { return }
        let now = apps.runningBundleIDs()
        let launched = now.subtracting(knownBundleIDs)
        let quit = knownBundleIDs.subtracting(now)
        knownBundleIDs = now
        let disconnectClosure: (String) -> Void = { [weak self] in self?.disconnect($0, auto: true) }
        for id in launched { launchIfTrusted(id) }
        // Every quit, not only the ones a rule still covers. `appTerminated`
        // consults `launched` — the record of what Helm actually did — and the
        // core's own comment says `rules` "cannot be trusted to say what a quit
        // should undo". This filter put the untrusted book back in front of it:
        // switch a rule off while its app is running, or let `VPNRules.valid`
        // drop it because the connection was renamed, and the quit never
        // arrived. `launched[bundleID]` then stayed set for good, and
        // `appLaunched`'s own guard refused every later launch — auto-connect
        // dead for the session with the row still showing the rule as on, and
        // the VPN Helm raised still up.
        for id in quit {
            core.appTerminated(id, disconnect: disconnectClosure)
        }
    }

    /// A launch acts only if the instance running under that identifier is signed
    /// as the app the person picked.
    ///
    /// **One gate, at the launch, and the quit follows from it.** `appTerminated`
    /// undoes only launches `core` recorded, and by the time an app has quit there
    /// is no bundle left to read a signature from — so refusing the launch is what
    /// makes the teardown unreachable too. That is the whole of the repair for a
    /// bundle anybody can build taking somebody's tunnel down by starting and
    /// stopping.
    ///
    /// Both routes into a launch come through here: the live one, and `activate()`
    /// replaying everything already running — a gate on only the first would let a
    /// forged bundle that was started before Helm straight through.
    ///
    /// The refusal is logged with its reason, because a rule that has quietly
    /// stopped firing looks exactly like one that fires every day
    /// (ARCHITECTURE.md § A rule that is being ignored is not a rule that is
    /// quiet). The identifier goes through `Redact.app`, like every other name in
    /// this file.
    private func launchIfTrusted(_ bundleID: String) {
        guard let rule = core.rules[bundleID] else { return }
        let verdict = VPNRuleTrust.judge(rule: rule, running: apps.identity(of: bundleID))
        guard verdict == .act else {
            HelmLog.shared.warn("vpn", "rule for \(Redact.app(bundleID)) did not fire: "
                + verdict.rawValue)
            return
        }
        core.appLaunched(bundleID, connect: { [weak self] in self?.connect($0, auto: true) })
    }

    // MARK: - Transport

    private func wireTransport() {
        localTransport.setHandler { [weak self] cmd in
            guard let self else { return Data() }
            guard let name = VPNCommand(rawValue: cmd.name) else { return Data() }
            switch name {
            case .toggle:
                self.toggleDefault()
            case .connect:
                if let payload = EngineReply.decode(VPNConnectionRef.self, from: cmd) {
                    self.connect(payload.name)
                }
            case .disconnect:
                if let payload = EngineReply.decode(VPNConnectionRef.self, from: cmd) {
                    self.disconnect(payload.name)
                }
            case .refresh:
                self.refresh()
            case .reloadRules:
                self.reloadRules()
            }
            return Data()
        }
    }

    /// What `emitState` last put on the wire — under the class's one lock.
    private var _lastEmitted: StatePayload?

    /// Emits the state — unless it is **equal in every field** to the last one
    /// sent: the poll above re-reads up to 26 times behind one connect, and
    /// each duplicate re-rendered every mounted page all night
    /// (`HiddenPageEventChurnBenchmark` prices that). Exact equality withholds
    /// only duplicates, never a change, and replay still serves late subscribers.
    private func emitState() {
        let payload = StatePayload(connections: connections,
                                    autoConnected: autoConnected.sorted(),
                                    defaultName: defaultConnection?.name,
                                    lastAutomation: lastAutomation,
                                    lastFailure: lastFailure,
                                    secretsBehindAPrompt: secretsBehindAPrompt)
        lock.lock(); let isDuplicate = payload == _lastEmitted
        _lastEmitted = payload; lock.unlock()
        guard !isDuplicate else { return }
        localTransport.emit(VPNEvent.state, encoding: payload)
    }
}
