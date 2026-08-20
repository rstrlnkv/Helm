// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime

/// Orchestrates VPN connect/disconnect/toggle (via `scutil --nc`) and per-app
/// auto-connect (VPNAutoConnectCore) against the injected ports. `activate()`/
/// `deactivate()` are the MODULE lifecycle (host enables/disables the module);
/// they also start/stop the auto-connect app observation. Blocking work runs
/// on `VPNWorkQueue`, which says why it exists.
///
/// **This file is over `file_length` and `type_body_length`, and stays over,
/// deliberately** — a warning nobody has explained is a warning the next person
/// silences. The obvious extraction, moving the strip's half into an
/// `extension VPNEngine` in a second file, is worse: `private` in Swift is
/// file-scoped, so it would turn `raisedAt`, `lastRegion`, `lastSpeed`, `lock`,
/// `_lastEmitted`, `interfaces`, `speed`, `work` and `emitState` internal —
/// trading the invariant this class is built on («touched only from the work
/// queue», enforced today by nothing else being able to see them) for a line
/// count. The real answer is to decompose the engine — the connect path with
/// its secret handling is one subject, the auto-connect book another, the strip
/// a third — and that is a change to somebody's live tunnels.
///
/// It is past the `file_length` **error** as well, which is not deliberate: it
/// says the next feature in this file has nowhere to go but that decomposition,
/// and the six repairs of 2026-08-20 were the next feature. `swiftlint lint
/// Sources/Modules/VPN/Engine/VPNEngine.swift` prints how far past.
public final class VPNEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down.
    ///
    /// It is the `module.vpn.*` prefix of every setting this module has ever
    /// saved and the category its log lines file under. `VPNDescriptor.id` is
    /// built from this rather than repeating it, the direction the descriptors
    /// already carry their command enums, so the two spellings are one. **The
    /// string itself never changes** — it names stored settings already on
    /// people's machines. The keychain service stays its `com.helm.vpn`
    /// literal on purpose: it is deployed under its own name
    /// (`KeychainCredentials`) and must not follow a rename.
    public static let moduleID = "vpn"

    private let settings: VPNSettings
    private let runner: VPNRunnerPort
    private let credentials: VPNCredentialsPort?
    private let apps: AppObserverPort
    private let network: NetworkWatchPort?
    private let interfaces: VPNInterfacePort
    private let exit: VPNExitPort
    private let speed: VPNSpeedPort
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
    /// The two pieces of work that leave the module's own queue — under the lock
    /// because they are started on the work queue and cancelled from the host's
    /// thread. `cancelWorkThatLeftTheQueue()`.
    private var _exitCheck: Task<Void, Never>?
    private var _speedRun: Task<Void, Never>?
    /// Whether a re-read is already armed for the burst of network
    /// notifications going on now — `networkChanged()`. Under the lock because
    /// the store delivers on its own queue and the re-read runs on the work
    /// queue.
    private var _networkChangePending = false

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
    /// When Helm saw the current tunnel come up, keyed by service id. Dropped
    /// when the service goes down, so a stamp can never outlive its tunnel and
    /// be read against the next one — macOS raises the next one on a different
    /// `utunN`, and an uptime spanning the gap is a fiction.
    ///
    /// Touched only from the work queue, like `core` and `knownBundleIDs` above
    /// and unlike the fields under the lock.
    private var raisedAt: [String: Date] = [:]
    /// Whether `--nc list` has ever been read successfully in this process.
    ///
    /// The question a connect has to ask before it can trust `status`, and the
    /// one field that separates «this tunnel is down» from «nobody has looked».
    /// Touched only from the work queue, like `raisedAt` above.
    private var hasReadTheList = false
    /// Where this Mac appears to be, from outside. **A fact about the machine's
    /// exit, not about a tunnel**, so it stays one value however many are up: it
    /// decorates whichever holds the route, and is dropped when one falls,
    /// because the route may have moved with it.
    private var lastRegion: String?
    /// When the last exit request that **came back empty** was started, and
    /// whether one is still out.
    ///
    /// Both touched only from the work queue, like `raisedAt` and `lastRegion`
    /// above: the request is started there and its answer comes back through
    /// `work.run`. They are the two halves of `VPNExitAsk.should` that are facts
    /// about this engine rather than about the network — and without the second
    /// of them one connect starts twenty-six requests, because that is how many
    /// times `poll` re-reads while a tunnel comes up.
    private var lastExitAsk: Date?
    private var askingExit = false
    /// Which ask the answer coming back belongs to.
    ///
    /// **A forced check replaces one that is still out** — a tunnel coming up
    /// is news and the request in flight was asked about the exit before it —
    /// and `Task.cancel()` does not make the cancelled one silent: the URL load
    /// throws, `regionCode()` answers nil, and the completion still runs. Two
    /// things went wrong through that seam, and both are the family CLAUDE.md
    /// calls «the last writer wins by scheduling»: the old run cleared
    /// `askingExit` while the new one was out, so the next refresh started a
    /// third request; and a late answer overwrote `lastRegion` with a reading
    /// taken for a route the Mac had left. The counter is what tells the two
    /// apart, so a superseded run writes nothing at all.
    private var exitAsk = 0
    /// The interface the default route was on at the last reading, so that the
    /// route moving can be noticed at all. Nil means «not read yet», which
    /// `VPNExitAsk.routeMoved` refuses to call a move.
    private var lastPrimary: String?
    /// Tunnels seen falling, and when — held until they come back or stay gone
    /// (`VPNDropSettle`).
    ///
    /// **Keyed by the configuration's id, and the name is carried beside it.**
    /// Keyed by name it was, for one commit, on the reasoning that the notice
    /// says a name — and `ANameIsNotAnIdentityTests` said what that costs: two
    /// configurations may share a display name, so a namesake coming up by
    /// itself would have read as «it came back» and swallowed the drop of the
    /// one a rule was actually holding. That test exists because the same
    /// mistake was made once before, one field over.
    ///
    /// Touched only from the work queue.
    private var fellAt: [String: (name: String, at: Date)] = [:]
    /// The last measurement taken **on each tunnel**, keyed by service id: a
    /// figure belongs to whichever held the route when it was taken and is kept
    /// when the route moves (`VPNExitVerdict.carriesTheDefaultRoute`). What
    /// drops it is that tunnel going, below.
    private var lastSpeed: [String: VPNSpeedReading] = [:]
    /// Which interface each connected tunnel is on, and what the tool said about
    /// its routing — dropped when it goes, and read once per tunnel for as long
    /// as the routing half is nobody's answer (`readInterfaces`).
    ///
    /// **Read from `scutil --nc status <name>`, not from the dynamic store.**
    /// The store wants a network service's id and `--nc list` answers with a
    /// configuration's; they are the same string only for classic PPP/IPSec, so
    /// the old lookup answered nil for every NetworkExtension tunnel and the
    /// strip was absent on every Mac (`VPNStatusParser`). Cached because that is
    /// another subprocess — 16 ms here — and `emitState` runs up to 26 times
    /// behind one connect, while a tunnel's `utunN` does not change while it is
    /// up: macOS raises the next one on a new interface, which is exactly why
    /// the entry is dropped the moment the tunnel is not connected.
    private var interfaceOf: [String: VPNStatusParser.Reading] = [:]
    /// **Which tunnel** a measurement is in flight for, by name, or nil — the
    /// engine's own fact, on the wire in every payload, because
    /// `VPNTunnelState.measuring` says what a page inferring it from a press
    /// gets wrong. Written on the work queue at both ends of a run. A name and
    /// not a `Bool`: the flag is per tunnel, and one boolean set every entry of
    /// the list, turning a spinner over tunnels nobody was measuring.
    private var measuringSpeed: String?
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

    /// **Name the three network ports in every test that builds one of these.**
    /// Their defaults are the real thing: `TraceExit` reaches a server and
    /// `NetworkQualitySpeed` runs a subprocess for `typicalRun` under load.
    /// Eleven `AutopilotEngine` tests took a default port that turned out to be
    /// the owner's own keychain and rolled their rules back (CLAUDE.md § a
    /// default argument naming a real port); `NoTestTakesAProductionPortTests`
    /// is this module's guard against the same afternoon.
    public init(settings: VPNSettings,
                runner: VPNRunnerPort,
                credentials: VPNCredentialsPort? = nil,
                apps: AppObserverPort,
                network: NetworkWatchPort? = nil,
                transport: LocalTransport = LocalTransport(),
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
        network?.startObserving { [weak self] in self?.networkChanged() }
    }

    /// How long the store has to go quiet before the list is re-read.
    ///
    /// A quarter of a second, chosen against what the store actually delivers
    /// rather than picked: the bursts in the owner's log arrive inside a single
    /// second — seven, seven, seven, six — and one connect is followed by five
    /// to eleven notifications in under half a second. Long enough to swallow a
    /// burst, short enough to be invisible beside the 0.7 s the poll already
    /// waits between its own re-reads.
    private static let networkSettle: TimeInterval = 0.25

    /// **One re-read per burst, not one per notification.**
    ///
    /// `SCDynamicStore` does not deliver one event for one thing happening: a
    /// tunnel coming up moves the global IPv4 entity, each service's IPv4
    /// entity and the Setup entity, and this engine subscribes to all three
    /// (`DynamicStoreNetworkWatch`). Every notification used to cost a
    /// `scutil --nc list` — a subprocess measured at 16 ms, on the queue every
    /// connect has to get through — and a line in a `LogTail` bounded at 1000,
    /// which is the heartbeat `ScanCoordinator` has an explicit rule against.
    ///
    /// The port carries no detail about what changed, so deciding how often to
    /// re-read is the engine's job and nobody else's. The flag is the whole
    /// coalescer: the first notification of a burst arms the re-read and says
    /// so once in the log, the rest of the burst are free, and the re-read
    /// clears the flag before it runs so a later change re-arms it.
    private func networkChanged() {
        lock.lock()
        let alreadyArmed = _networkChangePending
        _networkChangePending = true
        lock.unlock()
        // An observer that never fires and an observer that fires and finds
        // nothing changed look identical from outside the process, and the
        // release process triages dev builds against the log. One line per
        // burst, no names in it.
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
        network?.stopObserving()
        cancelWorkThatLeftTheQueue()
    }

    /// The backstop for the routes that do not go through `deactivate()`.
    /// ARCHITECTURE.md § "An observer outlives the thing it points at".
    deinit {
        network?.stopObserving()
        cancelWorkThatLeftTheQueue()
    }

    /// The exit check and the speed run, cancelled from outside rather than left
    /// to `deinit`.
    ///
    /// `Task { [weak self] in await self?.something() }` captures weakly only at
    /// the top: once the body starts it holds `self` for as long as it runs, so
    /// a request waiting on its eight-second timeout holds this engine whoever
    /// else has dropped it — and `deinit` cannot run to cancel it (CLAUDE.md
    /// § `Task { [weak self] … }`).
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
            HelmLog.shared.warn(Self.moduleID, "connection list unreadable; keeping the last answer")
            return
        }
        let parsed = VPNListParser.parseList(output)
        // Only past the guard above: a read that failed is not a reading, and a
        // connect that took this for one would be back to deciding «already up»
        // off an empty cache.
        hasReadTheList = true
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
        //
        // **Nothing is struck out here, and that is the whole of the settle.**
        // The books were emptied on this very read — the first one showing the
        // tunnel down, which is the read `VPNDropSettle` exists to distrust —
        // while only the *announcement* waited for the window. A three-second
        // re-handshake therefore cost Helm the tunnel: the loop below that
        // re-adopts a connected tunnel is gated on `_autoConnected`, which this
        // had just cleared, so nothing put it back and the next real drop was
        // unreportable for the rest of the session. The forgetting waits for
        // `settleDrops` to answer `.announce` now (`forgetWhatWasLost`), and
        // `.healed` leaves both books exactly as they were.
        let fallen = _cameUp.filter { !up.contains($0.key) }
        let stillUp = _cameUp.filter { up.contains($0.key) }
        // A name is only forgotten when nothing Helm watched come up still
        // carries it — the same rule as the report below, so the page's book and
        // the news agree. Asked of the other half of the same partition rather
        // than of what is left in `_cameUp`, because nothing has been taken out
        // of it: the two were one sentence while the fallen were struck out
        // first.
        let dropped = Set(fallen.values).subtracting(stillUp.values)
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
        // **Recorded, not announced.** A tunnel re-handshaking on a Wi-Fi change
        // is down for a few seconds, and this notice used to fire on the first
        // read that saw it — measured twice in two days of the owner's log, both
        // times healed within three seconds (`VPNDropSettle`).
        // `fallen` rather than `dropped`, because the pending has to be keyed by
        // the configuration; `dropped` is the name-level answer to «is this news
        // at all», and it still decides that.
        for (id, name) in fallen.sorted(by: { $0.value < $1.value })
        where dropped.contains(name) && fellAt[id] == nil {
            fellAt[id] = (name, now())
            HelmLog.shared.info(Self.moduleID, "seen down: \(Redact.vpn(name))")
            // **One wake-up per fall, scheduled here rather than from the
            // verdict.** A Mac where a tunnel simply went is a Mac where nothing
            // else is going to ask again, so the verdict needs a refresh of its
            // own — and scheduling it from `settleDrops` recurses without end
            // under `VPNWorkQueue.inline`, which runs a delayed block at once:
            // refresh → still waiting → schedule → refresh. Here the `where`
            // guard is what stops it, since the fall is already recorded by the
            // time the block runs.
            work.run(after: VPNDropSettle.window) { [weak self] in self?.refreshNow() }
        }
        settleDrops(parsed)
        // After the lock, because it asks what the page was last told — and the
        // question has to be asked before this reading is emitted over it.
        stampWhatCameUp(parsed)
        // **One question about this Mac, asked once for the whole refresh.**
        // Both of the calls below need it — the interface read to know whether
        // the tool's own routing flag is the reading that decides, the country
        // check to notice the route moving — and asking the store twice is
        // also two answers that can disagree inside one reading.
        let primary = interfaces.primaryInterface()
        readInterfaces(parsed, whileStoreSays: primary)
        // After `readInterfaces`, never before: the gate asks whether a tunnel
        // is up in the sense the strip means it — one this module has an
        // interface for — and that book is filled a line above.
        noticeTheRouteAndAskWhereWeAre(primary)
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
        HelmLog.shared.info(Self.moduleID, "connect \(Redact.vpn(name))\(auto ? " (auto)" : "")")
        // **The reading the next line has always claimed to take.** `activate()`
        // replays every running app, so a rule fires at launch — and nothing
        // refreshes first. `status` then answers off an empty cache, which is
        // `.unknown` for a tunnel that is up, and two separate things ride on
        // that answer being wrong. The secret goes on a command line for a
        // `--nc start` that changes nothing, which is the exposure `!alreadyUp`
        // below exists to avoid and does not; and the payload emitted at the end
        // of this method names no connections at all, so `wasDown` finds no
        // previous reading of the service and the tunnel Helm has just raised is
        // never stamped. Both were true of this Mac's own log, where every
        // launch-time connect settles on the poll's first read — 0.8 s, one poll
        // — with no `Connecting` in between for the poll's own readings to
        // supply the missing «it was down».
        //
        // One `--nc list`, and only where there is nothing to read from:
        // refreshing before every connect would be a subprocess per press, and
        // the answer this needs is only ever missing for the first one.
        if !hasReadTheList { refreshNow() }
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
            HelmLog.shared.info(Self.moduleID, "no usable secret for \(Redact.vpn(name)) and a "
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
        HelmLog.shared.info(Self.moduleID, "disconnect \(Redact.vpn(name))\(auto ? " (auto)" : "")")
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
            HelmLog.shared.warn(Self.moduleID, "\(verb.rawValue) \(Redact.vpn(name)): "
                + "no such configuration")
            lock.lock()
            _lastFailure = VPNFailure(name: name, reason: .noSuchService, verb: verb)
            lock.unlock()
        case .refused(let text):
            HelmLog.shared.warn(Self.moduleID, "\(verb.rawValue) \(Redact.vpn(name)) refused: \(text)")
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
    /// **`scutil` cannot answer «since when».** The list says `Connected` and
    /// nothing more, so the only honest stamp is Helm's own observation: a
    /// service down at the last reading and up at this one. Which also means one
    /// already up when the process started carries no stamp — see `wasDown`.
    private func stampWhatCameUp(_ parsed: [VPNConnection]) {
        for connection in parsed where connection.status.isConnected {
            guard raisedAt[connection.id] == nil, wasDown(connection.id) else { continue }
            raisedAt[connection.id] = now()
            // A tunnel coming up is news, so this one goes round the gate:
            // whatever country is on record was read for the route this may
            // have just taken over, and a quiet period is about not repeating
            // an unanswered question rather than about ignoring an event.
            checkExit(force: true)
        }
        let up = Set(parsed.filter(\.status.isConnected).map(\.id))
        // **Against what is up, not against `raisedAt`.** Keyed off the stamps
        // this misses every tunnel already up at launch — exactly the ones
        // carrying none (`wasDown`) — which then drew, dropped and raised again,
        // its predecessor's throughput on a new `utunN`.
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
    /// **Two steps and one order.** A country read for Wi-Fi is not a country
    /// for the tunnel that has just taken the route, and a stale answer is worse
    /// than an absent one: absent reads as «not known», stale reads as known.
    /// So the move is noticed first and the question asked second, in one pass —
    /// otherwise the drop would wait a refresh for the ask.
    ///
    /// The route is decided on here rather than in `tunnelStates`, which also
    /// reads it: that one is called from `emitState` and this decides something
    /// and writes it down, and a getter with a side effect on shared state is
    /// the defect Autopilot's `folders` records (CLAUDE.md). The reading itself
    /// is `refreshNow`'s, taken once for the refresh.
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
    /// The name is what the question takes — `scutil --nc status "<name>"` — and
    /// the name is what this module has everywhere else too, because
    /// `--nc start` takes one. Two configurations may share a display name, and
    /// the answer is then about whichever macOS picks; that ambiguity is the
    /// tool's own and is recorded at `_cameUp`, which carries it for the same
    /// reason.
    ///
    /// **Once per tunnel is right about the interface and was wrong about the
    /// routing flag.** The same `Reading` carries both, and only the first of
    /// them holds still: a tunnel's `utunN` does not change while it is up,
    /// while `IsPrimaryInterface` — whether this Mac's traffic is leaving
    /// through the tunnel — moves without the tunnel moving at all, on a
    /// Wi-Fi-to-Ethernet switch, a second tunnel taking the route or a captive
    /// network arriving. Cached for the life of the tunnel it was a local
    /// memory of a live external fact with no channel to say it had changed
    /// (CLAUDE.md), and the dangerous direction is the route leaving while the
    /// green tick stays.
    ///
    /// So the cache is kept exactly where the flag is dead weight. The
    /// parameter is the routing table's own answer, which is what
    /// `VPNExitVerdict.of` prefers whenever it has one; the tool's flag is
    /// consulted only when that is nil — «a Mac with no default route» and «the
    /// store could not be read» at once (`VPNInterfacePort.primaryInterface`) —
    /// and that is precisely when it has to be read again. On the ordinary Mac,
    /// where the store answers, this is still one subprocess per tunnel.
    private func readInterfaces(_ parsed: [VPNConnection], whileStoreSays primary: String?) {
        let up = Set(parsed.filter(\.status.isConnected).map(\.id))
        for id in interfaceOf.keys where !up.contains(id) { interfaceOf[id] = nil }
        for connection in parsed
        where connection.status.isConnected
            && (interfaceOf[connection.id] == nil || primary == nil) {
            let output = runner.run(["--nc", "status", connection.name]).output
            // Nil stays nil: a tunnel that is still coming up names no interface
            // yet, and the next refresh — there is always one, the poll sees to
            // that — asks again. A *re-read* that answers nothing keeps what was
            // read before instead: the tunnel is up, the last reading is the
            // last thing the tool said about it, and dropping the row out of the
            // strip on one short answer is news about nothing.
            interfaceOf[connection.id] = VPNStatusParser.reading(in: output)
                ?? interfaceOf[connection.id]
        }
    }

    /// **Which of the falls seen so far were losses**, asked at every refresh.
    ///
    /// A tunnel that is up again is forgotten without a word; one still down
    /// past `VPNDropSettle.window` is the drop this module's one interrupting
    /// notice exists for. The wake-up that makes a quiet Mac reach this verdict
    /// at all is scheduled where the fall is recorded, one per fall — every
    /// other refresh comes from something happening, and a tunnel that is simply
    /// gone is nothing happening.
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
                // The books are emptied here and nowhere else, so «Helm is
                // holding this tunnel» and «Helm has said it was lost» are the
                // same moment. Before the notice, because everything
                // downstream reads off those two books.
                forgetWhatWasLost(id: id, name: name)
                HelmLog.shared.info(Self.moduleID,
                                    "automatic connection dropped: \(Redact.vpn(name))")
                // `.dropped`, not `.disconnected`. Nobody asked for this one: the
                // network went, the server hung up, or somebody stopped it in
                // System Settings — and the person is now sending everything in
                // clear having last been told they were behind a tunnel. It is
                // the one firing here that can be set to arrive as a banner
                // while the rules stay quiet.
                recordAutomation(name, .dropped)
            }
        }
    }

    /// Strikes a tunnel whose loss has just been announced out of both books.
    ///
    /// **The other end of the settle window.** A fall is not a loss until
    /// `VPNDropSettle` says so, so nothing may be forgotten on the reading that
    /// merely saw the tunnel down — a NetworkExtension tunnel re-handshaking on
    /// a Wi-Fi change is down for three seconds and comes back, and Helm is
    /// still holding it.
    ///
    /// The name goes only when no configuration Helm watched come up still
    /// carries it, which is `refreshNow`'s own rule read at this end: two
    /// configurations may share a display name, and `_autoConnected` is what
    /// the quit rule hands back to `--nc stop`.
    private func forgetWhatWasLost(id: String, name: String) {
        lock.lock()
        _cameUp[id] = nil
        if !_cameUp.values.contains(name) { _autoConnected.remove(name) }
        lock.unlock()
    }

    /// Was this service **seen** down before this refresh.
    ///
    /// False when there is no previous reading at all, which is the first
    /// refresh of the process: a tunnel that was already up then was not seen
    /// coming up by anybody, and stamping it there would be Helm timing its own
    /// launch and calling it the tunnel's age.
    private func wasDown(_ id: String) -> Bool {
        lock.lock(); let previous = _lastEmitted; lock.unlock()
        guard let previous,
              let before = previous.connections.first(where: { $0.id == id })
        else { return false }
        return !before.status.isConnected
    }

    /// Every tunnel the strip can be about: the connected ones the tool has
    /// named an interface for, ordered by `VPNTunnelChoice.primaryFirst`, which
    /// says what that order is for. One with no reading is coming up and is left
    /// out rather than drawn empty — the next refresh asks.
    ///
    /// **One `sysctl` per tunnel per emission is what makes a list affordable.**
    /// `VPNInterfaceCounters.bytes` is a single `net.link.generic.ifdata` read
    /// measured 0.03 ms here, against the 16 ms subprocess `interfaceOf` caches.
    private func tunnelStates() -> [VPNTunnelState] {
        let primary = interfaces.primaryInterface()
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
    /// **When there is a tunnel up with no country to its name**, which is a
    /// state rather than an event — `VPNExitAsk` carries the whole rule and the
    /// story of the event this used to be. `force` is that event, still: a
    /// tunnel coming up is news and goes round the quiet period.
    ///
    /// This is the app's one request to a server that is not the update feed, so
    /// the gate is not decoration: every path into `refreshNow` reaches here,
    /// and there are a great many of them behind one connect.
    private func checkExit(force: Bool = false) {
        guard force || VPNExitAsk.should(tunnelIsUp: !interfaceOf.isEmpty,
                                         region: lastRegion, asking: askingExit,
                                         lastAsked: lastExitAsk, now: now())
        else { return }
        askingExit = true
        // Stamped as the request leaves rather than as it lands, so a run that
        // never comes back — the process going down mid-flight — cannot leave
        // the gate open.
        lastExitAsk = now()
        exitAsk += 1
        let mine = exitAsk
        let task = Task { [weak self] in
            // **Weakly across the await, the way `startMeasuring` already is.**
            // `guard let self` at the top captures weakly and then holds the
            // engine strongly for as long as the body runs — which here is the
            // eight seconds `VPNExitPort` may take — so `deinit` could not run
            // to cancel the task that was holding it (CLAUDE.md
            // § `Task { [weak self] … }`). The port is held instead, and it
            // points at nothing.
            guard let exit = self?.exit else { return }
            let region = await exit.regionCode()
            self?.work.run { [weak self] in
                guard let self, self.exitAsk == mine else { return }
                // The flag is cleared whatever came back — an empty answer is an
                // answer arriving, and leaving it set would close the question
                // for the life of the process. What keeps an empty answer from
                // being asked again straight away is the quiet period, which is
                // a clock rather than a flag.
                self.askingExit = false
                self.lastRegion = region
                // **An answer wipes the clock, and only an empty one leaves a
                // mark.** The quiet period separates two attempts that came back
                // with nothing; a run that answered has closed the question by
                // itself, and what reopens it is the route moving. Left standing
                // through a good answer it refused the re-read after a move for a
                // whole minute — so the tunnel came back onto the route wearing
                // no country at all, which is the defect one level down from the
                // one this gate was added for.
                if region != nil { self.lastExitAsk = nil }
                self.emitState()
            }
        }
        lock.lock(); let previous = _exitCheck; _exitCheck = task; lock.unlock()
        previous?.cancel()
    }

    /// One measurement, on request.
    ///
    /// **Nowhere near the module's serial queue.** `VPNWorkQueue` is one queue
    /// and every connect, disconnect and poll goes through it, while
    /// `networkQuality` holds the thread it runs on for `NetworkQualitySpeed.typicalRun` by
    /// design and up to the sixty of its deadline — so a run started there
    /// leaves the module deaf to a person pressing Connect for as long as it
    /// lasts. Off the cooperative pool as well (`offTheCooperativePool`): that
    /// pool has one thread per core and this would hold one of them for the same
    /// quarter of a minute. Only the state write comes back to the queue, the
    /// way `checkExit` already does.
    ///
    /// The decision about *whether* to measure is still the queue's, because it
    /// reads the connections: nothing up is nothing to measure.
    ///
    /// See `NetworkQualitySpeed` for why the run is not bound to the tunnel's
    /// own interface, and `VPNExitVerdict.carriesTheDefaultRoute` for why that
    /// makes this take a name and refuse every tunnel but one — here as well as
    /// in the view, a refusal living in a `body` being one a command goes round.
    ///
    /// The phase is the port's to name (`vpn.speed`), not this caller's.
    private func measureSpeed(_ name: String) {
        work.run { [weak self] in
            guard let self else { return }
            // **The refusal, and it is published.** Two things answer here: a
            // tunnel not carrying the traffic, and one gone between the press
            // and this queue, which the page's optimistic «measuring» races. A
            // silent return leaves the second with a spinner and no button under
            // it, a refresh over a quiet tunnel being withheld by the dedup —
            // `connectNow`'s rule for its own early return.
            //
            // **And the publication is forced**, because the dedup is what it
            // was being withheld by: a refusal moves no field of the payload,
            // so an ordinary `emitState()` here was the silent return it was
            // written to replace (`ARefusedMeasurementIsNotSilenceTests`).
            guard let target = self.tunnelStates().first(where: { $0.name == name }),
                  target.exit.carriesTheDefaultRoute else {
                self.emitState(force: true)
                return
            }
            // One run at a time, and this one **is** silent: the run already
            // going will say «not measuring» when it ends and nothing has
            // changed meanwhile. A second press would spend another twenty
            // seconds answering the question already being asked, and the first
            // ending would say the run had stopped while the second still ran.
            guard self.measuringSpeed == nil else { return }
            self.measuringSpeed = name
            // Before the waiting starts, so the page draws «measuring» whether
            // or not it asked — and the run has two ends on the wire, not one.
            self.emitState()
            self.startMeasuring(for: name)
        }
    }

    private func startMeasuring(for name: String) {
        let task = Task { [weak self] in
            // Weakly inside the pool closure too: the engine is not held for the
            // twenty seconds the tool takes, and a module switched off in the
            // middle of a run is dropped then rather than at the end of it.
            //
            // The two nils are one answer here — the tool refused, or the engine
            // went away while it ran — and neither is a figure, so they are
            // flattened at the read rather than carried as a shape nothing else
            // in this file has to think about.
            let reading: VPNSpeedReading? = await offTheCooperativePool { [weak self] in
                self?.speed.measure(onInterface: nil)
            } ?? nil
            self?.work.run { [weak self] in
                guard let self else { return }
                // **Every ending writes this, refusal included.** The reading may
                // be the one it already had, or nothing at all — a `-1009`, a
                // tool killed at its deadline — and over a quiet tunnel not one
                // other field of the payload will have moved. What makes the end
                // of a run news is the run's own state changing here.
                self.measuringSpeed = nil
                // **A refusal keeps the figure it had.** The reading is filed
                // under the tunnel it was taken on — a run whose tunnel went
                // mid-flight finds no id and keeps nothing — and an ending with
                // nothing to report writes nothing at all: `lastSpeed[id] = nil`
                // *removes* the key, so a `-1009` erased the number the card was
                // still showing and the button under it forgot it had ever been
                // pressed. What drops a figure is that tunnel going, above.
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

    // MARK: - Transport

    private func wireTransport() {
        localTransport.setHandler { [weak self] cmd in
            guard let self else { return Data() }
            guard let name = VPNCommand(rawValue: cmd.name) else { return Data() }
            switch name {
            case .toggle:
                self.toggleDefault()
            case .connect:
                self.named(cmd) { self.connect($0) }
            case .disconnect:
                self.named(cmd) { self.disconnect($0) }
            case .refresh:
                self.refresh()
            case .reloadRules:
                self.reloadRules()
            case .measureSpeed:
                self.named(cmd, self.measureSpeed)
            }
            return Data()
        }
    }

    /// The three commands that are **about a connection**, decoded one way —
    /// each did it at its own case until the third arrived.
    private func named(_ cmd: EngineCommand, _ act: (String) -> Void) {
        guard let ref = EngineReply.decode(VPNConnectionRef.self, from: cmd) else { return }
        act(ref.name)
    }

    /// What `emitState` last put on the wire — under the class's one lock.
    private var _lastEmitted: StatePayload?

    /// Emits the state — unless it is **equal in every field** to the last one
    /// sent: the poll above re-reads up to 26 times behind one connect, and
    /// each duplicate re-rendered every mounted page all night
    /// (`HiddenPageEventChurnBenchmark` prices that). Exact equality withholds
    /// only duplicates, never a change, and replay still serves late subscribers.
    ///
    /// Which is why the tunnel's byte counters cross in whole kilobytes: they
    /// move while nobody touches them, and at byte precision every one of the
    /// poll's re-reads would be a change (`VPNInterfaceCounters.onTheWire`).
    ///
    /// **`force` is for news the payload has no field for.** A refusal changes
    /// nothing about the module, so the payload it publishes is equal in every
    /// field to the last one and the guard below withholds it — which over a
    /// quiet tunnel is the whole of the answer the page was waiting for
    /// (`measureSpeed`). The stamp is taken either way, so a forced emission
    /// leaves the dedup saying exactly what it said before.
    private func emitState(force: Bool = false) {
        let payload = StatePayload(connections: connections,
                                    autoConnected: autoConnected.sorted(),
                                    defaultName: defaultConnection?.name,
                                    lastAutomation: lastAutomation,
                                    lastFailure: lastFailure,
                                    secretsBehindAPrompt: secretsBehindAPrompt,
                                    tunnels: tunnelStates())
        lock.lock(); let isDuplicate = payload == _lastEmitted
        _lastEmitted = payload; lock.unlock()
        guard force || !isDuplicate else { return }
        localTransport.emit(VPNEvent.state, encoding: payload)
    }
}
