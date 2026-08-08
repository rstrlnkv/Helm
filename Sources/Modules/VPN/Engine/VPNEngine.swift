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
    /// Which of those were ever observed up. Without it, "not up right now"
    /// cannot be told from "not up yet".
    private var _cameUp: Set<String> = []
    private var _lastAutomation: VPNAutomation?

    public var lastAutomation: VPNAutomation? {
        lock.lock(); defer { lock.unlock() }; return _lastAutomation
    }

    /// Test seam: lets a test tell "nothing was written here" from "nothing was
    /// ever written". Nothing in the app clears this.
    func clearLastAutomationForTesting() {
        lock.lock(); _lastAutomation = nil; lock.unlock()
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
            for id in launched {
                self.core.appLaunched(id,
                                      connect: { [weak self] in self?.connect($0, auto: true) },
                                      disconnect: { _ in })
            }
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
        let output = runner.run(["--nc", "list"])
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
        let up = Set(parsed.filter { $0.status.isUp }.map(\.name))
        _cameUp.formUnion(up.intersection(_autoConnected))
        let dropped = _autoConnected.subtracting(up).intersection(_cameUp)
        _autoConnected.subtract(dropped)
        _cameUp.subtract(dropped)
        lock.unlock()
        // Recorded outside the lock the names were collected under: sorted so
        // that when several go at once the last one written is the same on
        // every run.
        for name in dropped.sorted() {
            HelmLog.shared.info("vpn", "automatic connection dropped: \(Redact.vpn(name))")
            recordAutomation(name, .disconnected)
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
        if auto {
            // Read before the books are touched, so this asks what was true when
            // the rule asked, not what Helm has since written down.
            let alreadyUp = status(name).isUp
            // Owning it and announcing it are different questions: the quit rule
            // reads `_autoConnected`, so a tunnel already up is still Helm's to
            // take down when the app goes.
            lock.lock(); _autoConnected.insert(name); lock.unlock()
            // Announced only when Helm actually changed something. `--nc start`
            // on a tunnel that is up is a no-op, and `activate()` replays
            // `appLaunched` for every app that was already running — so a rule
            // whose app runs all day fired this at every launch of Helm, naming
            // a tunnel nobody had touched. Measured in the menu bar, not
            // reasoned about: the ring spun 0.8 s after each launch.
            if !alreadyUp { recordAutomation(name, .connected) }
        }
        var args = ["--nc", "start", name]
        // Known limitation: scutil takes the shared secret only as an argument,
        // and process arguments are readable by every process running as this
        // user while scutil lives (a fraction of a second, but not zero). There
        // is no stdin form — `nc` is not a command scutil's interactive mode
        // accepts. Closing this means driving NEVPNManager/NEConfiguration
        // instead of the tool, which is a rewrite of this path, not a patch.
        if let creds = credentials?.credentials(for: name), creds.secret?.isEmpty == false {
            if let u = creds.user, !u.isEmpty { args += ["--user", u] }
            if let p = creds.password, !p.isEmpty { args += ["--password", p] }
            if let s = creds.secret, !s.isEmpty { args += ["--secret", s] }
        }
        _ = runner.run(args)
        emitState()
        scheduleRefresh()
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
        if auto, wasUp { recordAutomation(name, .disconnected) }
        // Both books. `_cameUp` is the memory of "this one did come up", and a
        // name left in it outlives the session it belonged to: the next time
        // the same app launches and Helm raises the same VPN, the first refresh
        // — the one that exists precisely because it still reports the old
        // status — sees a name that is not up and *was* once up, and forgets it
        // immediately. Connect and disconnect are this module's ordinary
        // traffic, so that is the common path, not an edge.
        lock.lock(); _autoConnected.remove(name); _cameUp.remove(name); lock.unlock()
        _ = runner.run(["--nc", "stop", name])
        emitState()
        scheduleRefresh()
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

    /// True while any connection is still transitioning — the UI shows a
    /// spinner for these, so state must be re-polled until it settles.
    static func needsPoll(_ connections: [VPNConnection]) -> Bool {
        connections.contains(where: \.status.isTransitioning)
    }

    private var pollAttempts = 0
    private let maxPollAttempts = 25   // ~17s at 0.7s — covers slow IKEv2 handshakes

    private func scheduleRefresh() {
        pollAttempts = 0
        pollUntilSettled()
    }

    /// A single 0.6s re-read used to leave the spinner stuck when the real
    /// handshake outlived it; keep polling while a transition is in flight.
    /// Tests use a synchronous runner and assert on issued commands, not on
    /// this async refresh.
    private func pollUntilSettled() {
        work.run(after: 0.7) { [weak self] in
            guard let self else { return }
            self.refreshNow()
            if Self.needsPoll(self.connections), self.pollAttempts < self.maxPollAttempts {
                self.pollAttempts += 1
                self.pollUntilSettled()
            } else if Self.needsPoll(self.connections) {
                HelmLog.shared.warn("vpn", "still transitioning after \(self.pollAttempts) polls: "
                    + self.connections.map { "\(Redact.vpn($0.name))=\($0.status)" }
                        .joined(separator: ", "))
            } else {
                HelmLog.shared.info("vpn", "settled: "
                    + self.connections.map { "\(Redact.vpn($0.name))=\($0.status)" }
                        .joined(separator: ", "))
            }
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
        let connectAuto: (String) -> Void = { [weak self] in self?.connect($0, auto: true) }
        let disconnectClosure: (String) -> Void = { [weak self] in self?.disconnect($0, auto: true) }
        for id in launched where core.rules[id] != nil {
            core.appLaunched(id, connect: connectAuto, disconnect: disconnectClosure)
        }
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
            core.appTerminated(id, connect: connectAuto, disconnect: disconnectClosure)
        }
    }

    // MARK: - Transport

    /// Public because the page decodes it — see the note on KeepAwake's.
    public struct StatePayload: Codable {
        public let connections: [VPNConnection]
        public let autoConnected: [String]
        public let defaultName: String?
        /// The last firing Helm caused, if any. Optional, so the synthesized
        /// decoder reads it with `decodeIfPresent` and a payload written before
        /// this field existed still decodes — a throw here would cost the page
        /// its whole state for the sake of one field.
        /// `VPNAutomationRecordingTests` holds a payload without it.
        public let lastAutomation: VPNAutomation?
    }

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

    private func emitState() {
        let payload = StatePayload(connections: connections,
                                    autoConnected: autoConnected.sorted(),
                                    defaultName: defaultConnection?.name,
                                    lastAutomation: lastAutomation)
        localTransport.emit(VPNEvent.state, encoding: payload)
    }
}
