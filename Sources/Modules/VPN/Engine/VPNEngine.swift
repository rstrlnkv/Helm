// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime

/// Orchestrates VPN connect/disconnect (`scutil --nc`, and
/// `SCNetworkConnectionStart` for a start that carries a secret) and per-app
/// auto-connect (`VPNAutoConnectCore`) against the injected ports. Blocking work
/// runs on `VPNWorkQueue`, which says why it exists.
///
/// **This file is over `file_length` and `type_body_length` by design.** Moving
/// the strip's half into an `extension VPNEngine` in a second file would turn
/// the file-scoped `private` members internal, trading the invariant «touched
/// only from the work queue» for a line count.
public final class VPNEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down: the `module.vpn.*`
    /// prefix of every saved setting and the category of its log lines.
    /// **The string never changes.** The keychain service is deployed under its own
    /// name (`KeychainCredentials.service(for:)`) and does not follow it.
    public static let moduleID = "vpn"

    private let settings: VPNSettings
    private let runner: VPNRunnerPort
    private let credentials: VPNCredentialsPort?
    private let apps: AppObserverPort
    private let network: NetworkWatchPort?
    private let interfaces: VPNInterfacePort
    private let exit: VPNExitPort
    private let speed: VPNSpeedPort
    private let news: EngineNews<StatePayload>

    /// Written from the work queue and read from the UI, hence the lock.
    private let lock = NSLock()
    private var _connections: [VPNConnection] = []
    private var _autoConnected: Set<String> = []
    /// The last command this module sent that the tool did not accept, cleared
    /// by the next one it did. One at a time on purpose: a page listing every
    /// refusal it has ever seen is a log, and there is one of those.
    private var _lastFailure: VPNFailure?
    /// Which of those were ever observed up, **by the configuration's own id**.
    ///
    /// Without it, "not up right now" cannot be told from "not up yet". Keyed by
    /// id because macOS lets two configurations carry one display name, and a
    /// namesake's being up must not hide the drop of the tunnel a rule was
    /// holding. The name is kept beside the id because a configuration deleted
    /// between two reads is gone from the list and the drop still has to be named.
    ///
    /// `_autoConnected` stays a set of **names**: `--nc start`/`--nc stop` take a
    /// name, so what the quit rule owns has to be something it can take down.
    /// Helm asks for a name, macOS picks the configuration.
    private var _cameUp: [String: String] = [:]
    /// Which configurations Helm has no usable secret for (`VPNSecretBook`); under
    /// the lock, written from the work queue and read by the page.
    private var _secrets = VPNSecretBook()
    /// Which rule cannot fire however its app launches, and why — written with
    /// `core.rules` by `reloadRulesNow`, under the lock, published by `emitState`.
    private var _ruleRefusals: [String: VPNRuleTrust.Verdict] = [:]
    private var _lastAutomation: VPNAutomation?
    /// The two pieces of work that leave the module's own queue — under the lock
    /// because they are started on the work queue and cancelled from the host's
    /// thread. `cancelWorkThatLeftTheQueue()`.
    private var _exitCheck: Task<Void, Never>?
    private var _speedRun: Task<Void, Never>?
    /// Whether a re-read is already armed for the current burst of network
    /// notifications (`networkChanged()`). Under the lock: the store delivers on
    /// its own queue and the re-read runs on the work queue.
    private var _networkChangePending = false

    public var lastAutomation: VPNAutomation? {
        lock.lock(); defer { lock.unlock() }; return _lastAutomation
    }

    /// Test seam: nothing in the app clears this.
    func clearLastAutomationForTesting() {
        lock.lock(); _lastAutomation = nil; lock.unlock()
    }

    public var lastFailure: VPNFailure? { lock.withLock { _lastFailure } }

    /// The configurations a rule cannot raise, because their secret is in the
    /// System keychain and only a person's own gesture may open it. Published and
    /// drawn, not merely logged, so a rule that meets this at every launch of its
    /// app is seen on the page.
    public var secretsBehindAPrompt: [String] {
        lock.lock(); defer { lock.unlock() }; return _secrets.names
    }

    /// The rules that will not fire however their app launches, by bundle identifier
    /// (`VPNRuleTrust.refusal(of:)`): drawn as a note in the rules popover.
    public var ruleRefusals: [String: VPNRuleTrust.Verdict] {
        lock.lock(); defer { lock.unlock() }; return _ruleRefusals
    }

    public var connections: [VPNConnection] {
        lock.lock(); defer { lock.unlock() }; return _connections
    }
    public var autoConnected: Set<String> {
        lock.lock(); defer { lock.unlock() }; return _autoConnected
    }

    private var core = VPNAutoConnectCore(rules: [:])
    private var knownBundleIDs: Set<String> = []
    /// When Helm saw the current tunnel come up, keyed by service id. Dropped
    /// when the service goes down, so a stamp cannot be read against the next
    /// tunnel (macOS raises it on a different `utunN`). Work queue only, like
    /// `core` and `knownBundleIDs`.
    private var raisedAt: [String: Date] = [:]
    /// Whether `--nc list` has ever been read successfully in this process: what
    /// separates «this tunnel is down» from «nobody has looked». Work queue only.
    private var hasReadTheList = false
    /// The rules as saved, held while the list has never been read: filtering them
    /// against no connections would drop every one of them for good. `refreshNow`
    /// applies them at the first good read. Work queue only.
    private var rulesAwaitingTheList: [String: VPNAppRule]?
    /// Where this Mac appears to be, from outside. **A fact about the machine's
    /// exit, not about a tunnel**, so one value however many are up: dropped when
    /// a tunnel Helm stamped falls (`stampWhatCameUp`) or when the route moves
    /// (`noticeTheRouteAndAskWhereWeAre`).
    private var lastRegion: String?
    /// When the last exit request that **came back empty** was started, and
    /// whether one is still out. Work queue only; they are the two halves of
    /// `VPNExitAsk.should` that are facts about this engine, and without the
    /// second one a connect's poll starts a request per re-read.
    private var lastExitAsk: Date?
    private var askingExit = false
    /// Which ask the answer coming back belongs to.
    ///
    /// **A forced check replaces one that is still out**, and `Task.cancel()`
    /// does not make the cancelled one silent: its completion still runs. The
    /// counter makes a superseded run write nothing, so it cannot clear
    /// `askingExit` for the new one or overwrite `lastRegion` with a reading for
    /// a route the Mac has left.
    private var exitAsk = 0
    /// The interface the default route was on at the last reading, so that the
    /// route moving can be noticed at all. Nil means «not read yet», which
    /// `VPNExitAsk.routeMoved` refuses to call a move.
    private var lastPrimary: String?
    /// Tunnels seen falling, and when, held until they come back or stay gone
    /// (`VPNDropSettle`).
    ///
    /// **Keyed by the configuration's id, the name carried beside it**: a
    /// namesake coming up must not read as «it came back» and swallow the drop
    /// (`ANameIsNotAnIdentityTests`). Work queue only.
    private var fellAt: [String: (name: String, at: Date)] = [:]
    /// The last measurement taken **on each tunnel**, keyed by service id: a
    /// figure belongs to whichever held the route when it was taken and is kept
    /// when the route moves (`VPNExitVerdict.carriesTheDefaultRoute`). What
    /// drops it is that tunnel going, below.
    private var lastSpeed: [String: VPNSpeedReading] = [:]
    /// Which interface each connected tunnel is on, and what the tool said about
    /// its routing: dropped when it goes, and read once per tunnel as long as the
    /// routing half is nobody's answer (`readInterfaces`).
    ///
    /// **Read from `scutil --nc status <name>`, not from the dynamic store**,
    /// which wants a network service's id while `--nc list` answers with a
    /// configuration's (`VPNStatusParser`). Cached because it is a subprocess and
    /// `emitState` runs at every poll behind one connect.
    private var interfaceOf: [String: VPNStatusParser.Reading] = [:]
    /// **Which tunnel** a measurement is in flight for, by name, or nil — the
    /// engine's own fact, in every published state, because
    /// `VPNTunnelState.measuring` says what a page inferring it from a press
    /// gets wrong. Written on the work queue at both ends of a run. A name and
    /// not a `Bool`: the flag is per tunnel, and a boolean would spin every card.
    private var measuringSpeed: String?
    /// Under the lock: written by `activate()` and `deactivate()` on the host's
    /// thread, read by `appsChangedNow()` on the work queue.
    private var _running = false
    private var running: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _running }
        set { lock.lock(); _running = newValue; lock.unlock() }
    }
    private let work: VPNWorkQueue
    /// Injected so a firing's moment is a fact of the caller rather than of the
    /// machine — `VPNAutomation.spinPhase` measures from it.
    private let now: @Sendable () -> Date

    /// **Name the three network ports in every test that builds one of these.**
    /// Their defaults are the real thing: `TraceExit` reaches a server and
    /// `NetworkQualitySpeed` runs a subprocess for `typicalRun` under load.
    /// `NoTestTakesAProductionPortTests` is this module's guard.
    public init(settings: VPNSettings,
                runner: VPNRunnerPort,
                credentials: VPNCredentialsPort? = nil,
                apps: AppObserverPort,
                network: NetworkWatchPort? = nil,
                news: EngineNews<StatePayload> = EngineNews(),
                interfaces: VPNInterfacePort = DynamicStoreInterfaces(),
                exit: VPNExitPort = TraceExit(),
                speed: VPNSpeedPort = NetworkQualitySpeed(),
                now: @escaping @Sendable () -> Date = Date.init,
                work: VPNWorkQueue = .background) {
        self.now = now
        self.work = work
        self.settings = settings
        self.runner = runner
        self.credentials = credentials
        self.apps = apps
        self.network = network
        self.interfaces = interfaces
        self.exit = exit
        self.speed = speed
        self.news = news
    }

    // MARK: - ModuleEngine (module enabled/disabled)

    public func activate() {
        running = true
        // Read where reading is safe: `RunningApps` answers live only on the
        // main thread, and this runs from `ModuleHost.enable`.
        let launched = apps.runningBundleIDs()
        // Everything that touches `core` goes on the one serial queue that owns
        // it, and off the main thread because this shells out to scutil at launch.
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
        network?.startObserving { [weak self] in self?.networkChanged() }
    }

    /// How long after a burst's first notification the list is re-read: a
    /// connect is followed by several notifications in under half a second, and
    /// a quarter of a second stays invisible beside the poll's 0.7 s.
    private static let networkSettle: TimeInterval = 0.25

    /// **One re-read per settle, not one per notification.**
    ///
    /// A tunnel coming up moves three entities this engine subscribes to
    /// (`DynamicStoreNetworkWatch`), and a re-read costs a `scutil --nc list` and
    /// a log line. The port carries no detail about what changed, so how often to
    /// re-read is the engine's job: the first notification of a burst arms the
    /// re-read, the rest are free, and the re-read clears the flag before it runs.
    private func networkChanged() {
        lock.lock()
        let alreadyArmed = _networkChangePending
        _networkChangePending = true
        lock.unlock()
        // An observer that never fires and one that fires and finds nothing
        // changed look identical from outside the process. One line per arming,
        // no names in it.
        guard !alreadyArmed else { return }
        HelmLog.shared.info(Self.moduleID, "network state changed; re-reading")
        work.run(after: Self.networkSettle) { [weak self] in
            guard let self else { return }
            self.lock.lock(); self._networkChangePending = false; self.lock.unlock()
            self.refreshNow()
        }
    }

    public func deactivate() {
        running = false
        apps.stopObserving()
        network?.stopObserving()
        cancelWorkThatLeftTheQueue()
    }

    /// The backstop for the routes that do not go through `deactivate()`
    /// (Architecture/StateAndLifetime.md § An observer outlives the thing it points at).
    deinit {
        apps.stopObserving()
        network?.stopObserving()
        cancelWorkThatLeftTheQueue()
    }

    /// The exit check and the speed run, cancelled from outside rather than left
    /// to `deinit`: a `Task { [weak self] in ... }` holds `self` for as long as
    /// its body runs, so `deinit` cannot cancel it
    /// (Architecture/StateAndLifetime.md § An observer outlives the thing it points at).
    private func cancelWorkThatLeftTheQueue() {
        lock.lock()
        let inFlight = [_exitCheck, _speedRun]
        _exitCheck = nil
        _speedRun = nil
        lock.unlock()
        for task in inFlight { task?.cancel() }
    }

    // MARK: - VPN control

    public func refresh() {
        work.run { [weak self] in self?.refreshNow() }
    }

    /// One line for a read that did not answer, naming why; the caller keeps
    /// its last answer.
    private func logFailedRead(_ what: String, _ status: Int32) {
        HelmLog.shared.warn(Self.moduleID, "\(what) read failed (\(vpnReadFailureReason(status))); keeping the last answer")
    }

    /// The blocking half, always on the work queue.
    private func refreshNow() {
        let read = runner.read(["--nc", "list"], timeout: vpnReadDeadline)
        // A read that ran out of time or exited non-zero is not an answer even
        // if it printed a list: the exit status is read with the output.
        guard read.status == 0 else {
            logFailedRead("connection list", read.status)
            return
        }
        let output = read.output
        // Silence is not an answer: an empty list from a tool that exited 0 looks
        // like a Mac with no VPNs, and acting on it announces the connections
        // gone and makes the drop detection decide everything fell at once.
        guard VPNListParser.isReadable(output) else {
            HelmLog.shared.warn(Self.moduleID, "connection list unreadable; keeping the last answer")
            return
        }
        let parsed = VPNListParser.parseList(output)
        // Only past the guard above: a failed read is not a reading.
        let firstRead = !hasReadTheList
        hasReadTheList = true
        lock.lock()
        _connections = parsed
        // A VPN Helm raised can also drop on its own. "Not up" is not enough to
        // forget it by: the refresh after a connect usually still reports the old
        // status. What is forgotten is one that *came* up and then went, asked of
        // ids rather than names.
        let up = Set(parsed.filter(\.status.isUp).map(\.id))
        // The fall is read before anything new is adopted, so a namesake that came
        // up in the same breath is not mistaken for the tunnel that went.
        // **Nothing is struck out here, and that is the whole of the settle**: the
        // loop below that re-adopts a re-handshaking tunnel is gated on
        // `_autoConnected`. The forgetting waits for `settleDrops`
        // (`forgetWhatWasLost`); `.healed` leaves both books as they were.
        let fallen = _cameUp.filter { !up.contains($0.key) }
        let stillUp = _cameUp.filter { up.contains($0.key) }
        // A name is forgotten only when nothing Helm watched come up still
        // carries it, asked of the other half of the same partition.
        let dropped = Set(fallen.values).subtracting(stillUp.values)
        for connection in parsed where connection.status.isUp
            && _autoConnected.contains(connection.name) {
            _cameUp[connection.id] = connection.name
        }
        // The reverse channel for the secret book: a tunnel that is up needed
        // nothing from Helm after all, and a configuration deleted in System
        // Settings is nothing to draw a sentence about. Without it the notice
        // could never be cleared.
        _secrets.reconcile(against: parsed)
        lock.unlock()
        // Recorded outside the lock, sorted so the last one written is the same on
        // every run. **Recorded, not announced**: a tunnel re-handshaking on a Wi-Fi
        // change is down for a few seconds (`VPNDropSettle`). `fallen` rather than
        // `dropped`, because the pending is keyed by the configuration.
        for (id, name) in fallen.sorted(by: { $0.value < $1.value })
        where dropped.contains(name) && fellAt[id] == nil {
            fellAt[id] = (name, now())
            HelmLog.shared.info(Self.moduleID, "seen down: \(Redact.vpn(name))")
            // **One wake-up per fall, scheduled here rather than from the
            // verdict**: scheduling it from `settleDrops` recurses without end
            // under `VPNWorkQueue.inline`, which runs a delayed block at once.
            // Here the `where` guard stops it, the fall being recorded by then.
            work.run(after: VPNDropSettle.window) { [weak self] in self?.refreshNow() }
        }
        settleDrops(parsed)
        // After the lock, because it asks what the page was last told — and the
        // question has to be asked before this reading is emitted over it.
        stampWhatCameUp(parsed)
        // **One question about this Mac, asked once for the whole refresh**: its
        // three consumers, `readInterfaces`, `noticeTheRouteAndAskWhereWeAre` and
        // the final `emitState(primary:)`, share it, and two answers can disagree
        // inside one reading.
        let primary = interfaces.primaryInterface()
        readInterfaces(parsed, whileStoreSays: primary)
        // After `readInterfaces`, never before: the gate asks whether a tunnel
        // has an interface, and that book is filled a line above.
        noticeTheRouteAndAskWhereWeAre(primary)
        // The rules a reload could not filter come back with the first list, and
        // the apps already running are replayed through the same identity gate
        // as in `activate()`; without it a rule for an app running since before
        // never fires.
        if firstRead, let saved = rulesAwaitingTheList {
            rulesAwaitingTheList = nil
            applyRules(saved)
            if running { for id in knownBundleIDs { launchIfTrusted(id) } }
        }
        emitState(primary: .some(primary))
    }

    /// The person's door: a press is never an automatic act, so a caller cannot
    /// set the rules' flag. Exhaustive, so a new `VPNVerb` is a build error.
    public func press(_ verb: VPNVerb, on name: String) {
        switch verb {
        case .connect: connect(name, auto: false)
        case .disconnect: disconnect(name, auto: false)
        }
    }

    func connect(_ name: String, auto: Bool) {
        work.run { [weak self] in self?.connectNow(name, auto: auto) }
    }

    private func connectNow(_ name: String, auto: Bool) {
        HelmLog.shared.info(Self.moduleID, "connect \(Redact.vpn(name))\(auto ? " (auto)" : "")")
        // `activate()` replays every running app, so a rule can fire at launch
        // with nothing refreshed first, when `status` answers `.unknown` for a
        // tunnel that is up: the secret would be read for a start that changes
        // nothing, and the tunnel Helm raised would never be stamped. One
        // `--nc list`, and only where there is nothing to read from.
        if !hasReadTheList { refreshNow() }
        // Read before anything is asked of the tool, so this is what was true
        // when the rule asked rather than what Helm has since written down.
        let alreadyUp = auto ? status(name).isUp : false
        // **The secret never rides in an argument list** (`VPNRunnerPort`): the start
        // that carries one goes to the system in process, and every other start is
        // the bare `scutil --nc start <name>`.
        //
        // A tunnel already up answers like a configuration that keeps no secret, and
        // the read is not performed: `activate()` replays every running app, so a
        // rule whose app runs all day would otherwise read the secret at every
        // launch. `promptingAllowed: !auto` is about a different exposure
        // (`VPNCredentialsPort`).
        let step = alreadyUp ? VPNSecretBook.Step.nothingToSupply
                             : secretStep(for: name, auto: auto)
        let reply: VPNCommandReply
        switch step {
        case .supply(let creds):
            reply = .of(runner.start(name, supplying: creds))
        // Nothing is supplied either way. What separates the two is whether a
        // connection may be *announced* afterwards — read off `step` below,
        // where the announcement is.
        case .nothingToSupply, .tryWithoutIt:
            reply = .of(runner.run(["--nc", "start", name]), name: name, knownNames: knownNames)
        case .refuse:
            HelmLog.shared.info(Self.moduleID, "no usable secret for \(Redact.vpn(name)) and a "
                + "rule may not ask for one; not attempted")
            // The one publication point, on the early return as well: a path that
            // skips it leaves the screen holding whatever it had.
            emitState()
            return
        case .unreadable:
            HelmLog.shared.warn(Self.moduleID, "the secret of \(Redact.vpn(name)) could not be read; "
                + "not attempted")
            // Only the person's press is answered on screen; a rule has no one
            // pressing, and the log line is its record.
            if !auto {
                lock.withLock { _lastFailure = VPNFailure(name: name, reason: .secretUnreadable, verb: .connect) }
            }
            emitState()
            return
        }
        report(reply, verb: .connect, name: name)
        // **Announced after the tool answered, and only what it did**, so a
        // configuration renamed in System Settings is not announced connected.
        // Owning it and announcing it are different questions: the quit rule
        // reads `_autoConnected`, so a tunnel already up is Helm's to take down,
        // but neither may be claimed for a command the tool refused.
        if auto, reply == .accepted {
            lock.lock(); _autoConnected.insert(name); lock.unlock()
            // Only when Helm actually changed something: `--nc start` on a tunnel
            // that is up is a no-op, and `activate()` replays every running app.
            //
            // **And never for a start Helm knowingly under-supplied**: `--nc
            // start` answers nothing either way, so the ring would light while
            // the page says the rule could not fire. Helm owns the tunnel either
            // way, so only the announcement is held back.
            if !alreadyUp, step != .tryWithoutIt { recordAutomation(name, .connected) }
        }
        emitState()
        if reply == .accepted { poll(name, following: .connect) }
    }

    func disconnect(_ name: String, auto: Bool) {
        work.run { [weak self] in self?.disconnectNow(name, auto: auto) }
    }

    private func disconnectNow(_ name: String, auto: Bool) {
        HelmLog.shared.info(Self.moduleID, "disconnect \(Redact.vpn(name))\(auto ? " (auto)" : "")")
        // Read before the books are touched, mirroring the connect side: a
        // teardown of a tunnel already down is a no-op, and announcing it would
        // name a disconnection the person never had.
        let wasUp = status(name).isUp
        let reply = VPNCommandReply.of(runner.run(["--nc", "stop", name]), name: name,
                                       knownNames: knownNames)
        report(reply, verb: .disconnect, name: name)
        // Recorded only after the tool accepted: a refused teardown leaves the
        // tunnel up, and Helm must still own it to report its real drop.
        //
        // Both books, when the tool did stop it: a name left in `_cameUp`
        // outlives its session, and the next refresh, still reporting the old
        // status, would see a name that was up once and forget it at once.
        if reply == .accepted {
            lock.lock()
            _autoConnected.remove(name)
            // By the name it was raised under, though the book is keyed by id:
            // `--nc stop` names a name, so everything Helm was watching under
            // that name is what this took down.
            _cameUp = _cameUp.filter { $0.value != name }
            lock.unlock()
            if auto, wasUp { recordAutomation(name, .disconnected) }
        }
        emitState()
        if reply == .accepted { poll(name, following: .disconnect) }
    }

    /// What a connect does about the secret this configuration needs, and the
    /// book's record of it, in one step under the lock the books share.
    ///
    /// The port answers «keeps no secret» (IKEv2) apart from «there is one and
    /// I may not read it», or a rule would announce a connection nobody had.
    /// The rule for each answer is `VPNSecretBook.step`, where it is pure and tested.
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

    func status(_ name: String) -> VPNStatus {
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
    /// **Not «is anything transitioning»**: the refresh after a connect usually
    /// still reports `Disconnected`, which is not a transition, and a poll that
    /// stopped there would never wait for a slow IKEv2 handshake. Asked of every
    /// namesake, like `status(_:)`: Helm asks for a name and macOS picks the
    /// configuration.
    static func settled(_ connections: [VPNConnection],
                        into wanted: VPNStatus, for name: String) -> Bool {
        connections.contains { $0.name == name && $0.status == wanted }
    }

    private var pollAttempts = 0
    private let maxPollAttempts = 25   // ~17s at 0.7s — covers slow IKEv2 handshakes

    /// Keeps polling until the command has arrived.
    ///
    /// **Only a command the tool accepted is followed**: waiting for a name
    /// `scutil` answered `No service` about would spend all 25 attempts on a
    /// tunnel never asked to come up. The ceiling stands under the other
    /// unresolvable case, a handshake that fails silently and ends at
    /// `Disconnected`. Tests use a synchronous runner, so a poll's length is a
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
                HelmLog.shared.info(Self.moduleID, "settled: " + trail)
            } else if self.pollAttempts < self.maxPollAttempts {
                self.pollAttempts += 1
                self.pollUntilSettled(name, wanted)
            } else {
                HelmLog.shared.warn(Self.moduleID, "\(Redact.vpn(name)) never reached \(wanted) after "
                    + "\(self.pollAttempts) polls: " + trail)
            }
        }
    }

    /// What the tool said, in the trail and in the state.
    ///
    /// `scutil` exits 0 whatever happens and puts its complaint on stdout, so
    /// this is where a rule pointing at a renamed configuration is heard. The name
    /// is redacted in the log; `_lastFailure` carries it unredacted because the
    /// screen may name what the person configured. The verb is the module's own
    /// enum, so the log word and the sentence cannot drift apart.
    private func report(_ reply: VPNCommandReply, verb: VPNVerb, name: String) {
        switch reply {
        case .accepted:
            lock.withLock { _lastFailure = nil }
        case .noSuchService:
            HelmLog.shared.warn(Self.moduleID, "\(verb.rawValue) \(Redact.vpn(name)): "
                + "no such configuration")
            lock.withLock { _lastFailure = VPNFailure(name: name, reason: .noSuchService, verb: verb) }
        case .refused(let text):
            HelmLog.shared.warn(Self.moduleID, "\(verb.rawValue) \(Redact.vpn(name)) refused: \(text)")
            lock.withLock { _lastFailure = VPNFailure(name: name, reason: .refused, verb: verb) }
        }
    }

    // MARK: - Auto-connect

    public func reloadRules() {
        work.run { [weak self] in self?.reloadRulesNow() }
    }

    private func reloadRulesNow() {
        // Superseded by the rules read below, so the read inside `refreshNow` has
        // nothing stale to apply.
        rulesAwaitingTheList = nil
        refreshNow()
        let saved = VPNRules.decode(settings.rulesJSON)
        if hasReadTheList {
            applyRules(saved)
        } else {
            // **No list, no filter**: against an empty one every rule is "for a
            // VPN that is gone". The first good read applies them and replays the
            // apps already running, as `activate()` does.
            rulesAwaitingTheList = saved
            applyRules([:])
        }
        emitState()
    }

    /// Keeps the rules whose VPN is in the list and records which of them cannot
    /// fire. Each rule the filter drops is logged here, once per filter.
    private func applyRules(_ saved: [String: VPNAppRule]) {
        core.rules = VPNRules.valid(saved, against: connections)
        for id in saved.keys.sorted() where core.rules[id] == nil {
            HelmLog.shared.info(Self.moduleID, "rule for \(Redact.app(id)) dropped: its connection is not in the list")
        }
        lock.lock()
        _ruleRefusals = core.rules.compactMapValues(VPNRuleTrust.refusal(of:))
        lock.unlock()
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
        // Every quit, not only the ones a rule still covers: `appTerminated`
        // consults `launched`, the record of what Helm did, and filtering by the
        // rules would leave `launched[bundleID]` set for good after a rule was
        // switched off or dropped, refusing every later launch.
        for id in quit {
            core.appTerminated(id, disconnect: disconnectClosure)
        }
    }

    /// A launch acts only if the instance running under that identifier is signed
    /// as the app the person picked.
    ///
    /// **One gate, at the launch, and the quit follows from it**: `appTerminated`
    /// undoes only launches `core` recorded, and by the time an app has quit
    /// there is no bundle left to read a signature from. Both routes come through
    /// here, the live one and `activate()` replaying what already runs.
    ///
    /// The refusal is logged with its reason, because a rule that has quietly
    /// stopped firing looks exactly like one that fires every day
    /// (Architecture/VPN.md). The identifier goes through `Redact.app`.
    private func launchIfTrusted(_ bundleID: String) {
        guard let rule = core.rules[bundleID] else { return }
        let verdict = VPNRuleTrust.judge(rule: rule, running: apps.identity(of: bundleID))
        guard verdict == .act else {
            HelmLog.shared.warn(Self.moduleID, "rule for \(Redact.app(bundleID)) did not fire: "
                + verdict.rawValue)
            return
        }
        core.appLaunched(bundleID, connect: { [weak self] in self?.connect($0, auto: true) })
    }

    // MARK: - What the strip is told

    /// Notes the moment a tunnel came up, and forgets what belonged to one that
    /// has gone.
    ///
    /// `--nc list` cannot answer «since when»; `--nc status` can
    /// (`VPNStatusParser.Reading.since`), so this stamp is the fallback: Helm's
    /// own observation of a service down at the last reading and up at this one.
    private func stampWhatCameUp(_ parsed: [VPNConnection]) {
        for connection in parsed where connection.status.isConnected {
            guard raisedAt[connection.id] == nil, wasDown(connection.id) else { continue }
            raisedAt[connection.id] = now()
            // A tunnel coming up is news and goes round the gate: the country on
            // record was read for the route this may have taken over.
            checkExit(force: true)
        }
        let up = Set(parsed.filter(\.status.isConnected).map(\.id))
        // **Against what is up, not against `raisedAt`**: the stamps miss every
        // tunnel already up at launch, which would then wear its predecessor's
        // throughput on a new `utunN`.
        for id in lastSpeed.keys where !up.contains(id) { lastSpeed[id] = nil }
        let fallen = raisedAt.keys.filter { !up.contains($0) }
        guard !fallen.isEmpty else { return }
        for id in fallen { raisedAt[id] = nil }
        // The country is about the machine's exit rather than about a tunnel,
        // and a tunnel falling can move the route, so it is dropped outright
        // and asked again when something comes up.
        lastRegion = nil
    }

    /// Drops a country that belongs to a route the machine has since left, then
    /// asks for one if there is none.
    ///
    /// **Two steps and one order.** A stale country is worse than an absent one
    /// (absent reads as «not known»), so the move is noticed first and the
    /// question asked second, in one pass.
    ///
    /// The route is decided on here rather than in `tunnelStates`, which is a
    /// getter and must not change shared state. The reading itself is
    /// `refreshNow`'s, taken once for the refresh.
    private func noticeTheRouteAndAskWhereWeAre(_ primary: String?) {
        if VPNExitAsk.routeMoved(from: lastPrimary, to: primary) { lastRegion = nil }
        // Only a reading that answered is remembered: nil is «no network» and
        // «could not read» at once, so storing it would make the next real
        // answer look like a move.
        if primary != nil { lastPrimary = primary }
        checkExit()
    }

    /// Asks the tool which interface each tunnel that is up came up on, once per
    /// tunnel, and forgets one that has gone.
    ///
    /// The name is what the question takes (`--nc start` takes one too); two
    /// configurations may share it, and the ambiguity is the tool's own
    /// (see `_cameUp`).
    ///
    /// **Once per tunnel is right about the interface and wrong about the
    /// routing flag.** `utunN` holds still while a tunnel is up;
    /// `IsPrimaryInterface` moves without the tunnel moving (a Wi-Fi-to-Ethernet
    /// switch, a second tunnel, a captive network), and the dangerous direction
    /// is the route leaving while the green dot stays. So the cache is kept only
    /// where the flag is dead weight: `primary` is the routing table's answer,
    /// which `VPNExitVerdict.of` prefers; when that is nil
    /// (`VPNInterfacePort.primaryInterface`) the read is repeated.
    private func readInterfaces(_ parsed: [VPNConnection], whileStoreSays primary: String?) {
        let up = Set(parsed.filter(\.status.isConnected).map(\.id))
        for id in interfaceOf.keys where !up.contains(id) { interfaceOf[id] = nil }
        for connection in parsed
        where connection.status.isConnected
            && (interfaceOf[connection.id] == nil || primary == nil) {
            let read = runner.read(["--nc", "status", connection.name], timeout: vpnReadDeadline)
            guard read.status == 0 else {
                logFailedRead("status of \(Redact.vpn(connection.name))", read.status)
                continue
            }
            let output = read.output
            // Nil stays nil: a tunnel still coming up names no interface yet, and
            // the next refresh asks again. A *re-read* that answers nothing keeps
            // what was read before.
            interfaceOf[connection.id] = VPNStatusParser.reading(in: output)
                ?? interfaceOf[connection.id]
        }
    }

    /// **Which of the falls seen so far were losses**, asked at every refresh.
    ///
    /// A tunnel that is up again is forgotten without a word; one still down past
    /// `VPNDropSettle.window` is the drop the module's one interrupting notice is
    /// for. The wake-up that makes a quiet Mac reach this verdict is scheduled
    /// where the fall is recorded.
    private func settleDrops(_ parsed: [VPNConnection]) {
        guard !fellAt.isEmpty else { return }
        // **By id.** A tunnel of the same *name* being up is not this one coming
        // back — see the note on `fellAt`.
        let upNow = Set(parsed.filter(\.status.isUp).map(\.id))
        for (id, fall) in fellAt {
            let name = fall.name
            switch VPNDropSettle.verdict(fellAt: fall.at, isUpNow: upNow.contains(id),
                                         now: now()) {
            case .healed:
                fellAt[id] = nil
                HelmLog.shared.info(Self.moduleID, "came back before the notice: \(Redact.vpn(name))")
            case .waiting:
                break
            case .announce:
                fellAt[id] = nil
                // The books are emptied here and nowhere else, before the notice,
                // because everything downstream reads off them.
                forgetWhatWasLost(id: id, name: name)
                HelmLog.shared.info(Self.moduleID,
                                    "automatic connection dropped: \(Redact.vpn(name))")
                // `.dropped`, not `.disconnected`: nobody asked for this one, and
                // the person is now sending everything in clear having last been
                // told they were behind a tunnel.
                recordAutomation(name, .dropped)
            }
        }
    }

    /// Strikes a tunnel whose loss has just been announced out of both books.
    ///
    /// **The other end of the settle window**: nothing may be forgotten on the
    /// reading that merely saw the tunnel down. The name goes only when no
    /// configuration Helm watched come up still carries it (`refreshNow`'s rule),
    /// because `_autoConnected` is what the quit rule hands back to `--nc stop`.
    private func forgetWhatWasLost(id: String, name: String) {
        lock.lock()
        _cameUp[id] = nil
        if !_cameUp.values.contains(name) { _autoConnected.remove(name) }
        lock.unlock()
    }

    /// Was this service **seen** down before this refresh. False when there is no
    /// previous reading at all: a tunnel already up at the first refresh was seen
    /// coming up by nobody, and stamping it would be Helm timing its own launch.
    private func wasDown(_ id: String) -> Bool {
        lock.lock(); let previous = _lastEmitted; lock.unlock()
        guard let previous,
              let before = previous.connections.first(where: { $0.id == id })
        else { return false }
        return !before.status.isConnected
    }

    /// Every tunnel the strip can be about: the connected ones the tool has
    /// named an interface for, ordered by `VPNTunnelChoice.primaryFirst`. One
    /// with no reading is coming up and is left out; the next refresh asks.
    ///
    /// One `sysctl` per tunnel per emission is affordable; the subprocess is
    /// what `interfaceOf` caches.
    ///
    /// `primary` is the reading a refresh already took, passed on so the tunnels
    /// are judged by the answer the rest of that refresh used; nil asks afresh.
    private func tunnelStates(primary reading: String?? = nil) -> [VPNTunnelState] {
        let primary = reading ?? interfaces.primaryInterface()
        return VPNTunnelChoice.primaryFirst(connections.filter(\.status.isConnected)
            .compactMap { connection in
                interfaceOf[connection.id].map {
                    VPNTunnelState(connection, on: $0, primary: primary,
                                   since: raisedAt[connection.id],
                                   carried: interfaces.bytes(on: $0.interface),
                                   speed: lastSpeed[connection.id], region: lastRegion,
                                   measuring: measuringSpeed == connection.name)
                }
            })
    }

    /// Asks the outside world where this Mac appears to be.
    ///
    /// When a tunnel is up with no country to its name (`VPNExitAsk`); `force` is
    /// a tunnel coming up, which goes round the quiet period. The app's one
    /// request to a server that is not the update feed, so the gate is not
    /// decoration: every path into `refreshNow` reaches here.
    private func checkExit(force: Bool = false) {
        guard force || VPNExitAsk.should(tunnelIsUp: !interfaceOf.isEmpty,
                                         region: lastRegion, asking: askingExit,
                                         lastAsked: lastExitAsk, now: now())
        else { return }
        askingExit = true
        // Stamped as the request leaves, so a run that never comes back cannot
        // leave the gate open.
        lastExitAsk = now()
        exitAsk += 1
        let mine = exitAsk
        let task = Task { [weak self] in
            // **Weakly across the await**: `guard let self` would hold the engine
            // for the eight seconds `VPNExitPort` may take, and `deinit` could not
            // cancel the task (Architecture/StateAndLifetime.md § An observer outlives the thing it points at).
            // The port is held instead.
            guard let exit = self?.exit else { return }
            let region = await exit.regionCode()
            self?.work.run { [weak self] in
                guard let self, self.exitAsk == mine else { return }
                // The flag is cleared whatever came back: leaving it set would
                // close the question for the life of the process. What keeps an
                // empty answer from being asked again at once is the quiet period.
                self.askingExit = false
                self.lastRegion = region
                // **An answer wipes the clock, and only an empty one leaves a
                // mark**: left standing through a good answer it would refuse the
                // re-read after a route move.
                if region != nil { self.lastExitAsk = nil }
                self.emitState()
            }
        }
        lock.lock(); let previous = _exitCheck; _exitCheck = task; lock.unlock()
        previous?.cancel()
    }

    /// One measurement, on request.
    ///
    /// **Nowhere near the module's serial queue**: `networkQuality` holds its
    /// thread for `NetworkQualitySpeed.typicalRun` and up to sixty seconds, so a
    /// run started there leaves the module deaf to a press of Connect. Off the
    /// cooperative pool as well (`offTheCooperativePool`); only the state write
    /// comes back to the queue. Whether to measure is still the queue's decision,
    /// because it reads the connections.
    ///
    /// See `NetworkQualitySpeed` for why the run is not bound to the tunnel's
    /// interface, and `VPNExitVerdict.carriesTheDefaultRoute` for why this takes
    /// a name and refuses every tunnel but one, here as well as in the view.
    public func measureSpeed(_ name: String) {
        work.run { [weak self] in
            guard let self else { return }
            // **The refusal is published, and forced**: a tunnel not carrying the
            // traffic, or one gone between the press and this queue, moves no
            // field of the payload, so an ordinary `emitState()` would say nothing
            // (`ARefusedMeasurementIsNotSilenceTests`).
            guard let target = self.tunnelStates().first(where: { $0.name == name }),
                  target.exit.carriesTheDefaultRoute else {
                self.emitState(force: true)
                return
            }
            // One run at a time, and this one **is** silent: the run already
            // going says «not measuring» when it ends.
            guard self.measuringSpeed == nil else { return }
            self.measuringSpeed = name
            // Before the waiting starts, so the page draws «measuring» whether
            // or not it asked.
            self.emitState()
            self.startMeasuring(for: name)
        }
    }

    private func startMeasuring(for name: String) {
        let task = Task { [weak self] in
            // Weakly inside the pool closure too: a module switched off in the
            // middle of a run is dropped then, not at the end of it. The two nils
            // (tool refused, engine gone) are flattened at the read.
            let reading: VPNSpeedReading? = await offTheCooperativePool { [weak self] in
                self?.speed.measure(onInterface: nil)
            } ?? nil
            self?.work.run { [weak self] in
                guard let self else { return }
                // **Every ending writes this, refusal included**: over a quiet
                // tunnel the run's own state changing is the only news.
                self.measuringSpeed = nil
                // **A refusal keeps the figure it had**: `lastSpeed[id] = nil`
                // would remove the key and erase the number the card still shows.
                // What drops a figure is that tunnel going.
                if let id = self.connections.first(where: { $0.name == name })?.id,
                   let reading {
                    self.lastSpeed[id] = reading
                }
                self.emitState()
            }
        }
        lock.lock(); let previous = _speedRun; _speedRun = task; lock.unlock()
        previous?.cancel()
    }

    // MARK: - What the engine says

    /// The state, as a stream: the latest one first, then every later one, in
    /// order, a forced re-emission included.
    ///
    /// **Registered before this returns, in the one hold of the lock that replays
    /// what was last said** (`EngineNews.stream`): reading and then subscribing
    /// leaves a window an emit falls into. Synchronous and not actor-isolated, so
    /// the model takes it in its own `init`, before its first suspension.
    public func stream() -> AsyncStream<StatePayload> { news.stream() }

    public var subscriberCount: Int { news.subscriberCount }

    /// What `emitState` last said — under the class's one lock.
    private var _lastEmitted: StatePayload?

    /// Emits the state unless it is **equal in every field** to the last one
    /// sent: the poll re-reads many times behind one connect, and each duplicate
    /// would re-render every mounted page. Byte counters therefore cross in
    /// whole kilobytes (`VPNInterfaceCounters.onTheWire`).
    ///
    /// **`force` is for news the payload has no field for.** A refused
    /// measurement (`measureSpeed`) changes nothing, so the guard below would
    /// withhold it. The stamp is taken either way.
    private func emitState(force: Bool = false, primary: String?? = nil) {
        let payload = StatePayload(connections: connections,
                                    autoConnected: autoConnected.sorted(),
                                    lastAutomation: lastAutomation,
                                    lastFailure: lastFailure,
                                    secretsBehindAPrompt: secretsBehindAPrompt,
                                    ruleRefusals: ruleRefusals,
                                    tunnels: tunnelStates(primary: primary))
        lock.lock(); let isDuplicate = payload == _lastEmitted
        _lastEmitted = payload; lock.unlock()
        guard force || !isDuplicate else { return }
        news.say(payload)
    }
}
