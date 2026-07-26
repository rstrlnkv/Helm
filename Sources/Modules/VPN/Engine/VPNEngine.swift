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
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    /// Written from the work queue and read from the UI, hence the lock — the
    /// class was `@unchecked Sendable` with no synchronisation at all, and an
    /// array written from two threads is not a race you get a warning for.
    private let lock = NSLock()
    private var _connections: [VPNConnection] = []
    private var _autoConnected: Set<String> = []

    public var connections: [VPNConnection] {
        lock.lock(); defer { lock.unlock() }; return _connections
    }
    public var autoConnected: Set<String> {
        lock.lock(); defer { lock.unlock() }; return _autoConnected
    }

    private var core = VPNAutoConnectCore(rules: [:])
    private var knownBundleIDs: Set<String> = []
    private var running = false
    private let work: VPNWorkQueue

    public init(settings: VPNSettings,
                runner: VPNRunnerPort,
                credentials: VPNCredentialsPort? = nil,
                apps: AppObserverPort,
                transport: LocalTransport = LocalTransport(),
                work: VPNWorkQueue = .background) {
        self.work = work
        self.settings = settings
        self.runner = runner
        self.credentials = credentials
        self.apps = apps
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
    }

    public func deactivate() {
        running = false
    }

    // MARK: - VPN control

    public func refresh() {
        work.run { [weak self] in self?.refreshNow() }
    }

    /// The blocking half, always on the work queue.
    private func refreshNow() {
        let parsed = VPNListParser.parseList(runner.run(["--nc", "list"]))
        lock.lock(); _connections = parsed; lock.unlock()
        emitState()
    }

    public var defaultConnection: VPNConnection? {
        if let live = connections.first(where: { $0.status == .connected || $0.status == .connecting }) {
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
        if target.status == .connected || target.status == .connecting {
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
        if auto { lock.lock(); _autoConnected.insert(name); lock.unlock() }
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

    public func disconnect(_ name: String) {
        work.run { [weak self] in self?.disconnectNow(name) }
    }

    private func disconnectNow(_ name: String) {
        HelmLog.shared.info("vpn", "disconnect \(Redact.vpn(name))")
        lock.lock(); _autoConnected.remove(name); lock.unlock()
        _ = runner.run(["--nc", "stop", name])
        emitState()
        scheduleRefresh()
    }

    public func status(_ name: String) -> VPNStatus {
        connections.first(where: { $0.name == name })?.status ?? .unknown
    }

    /// True while any connection is still transitioning — the UI shows a
    /// spinner for these, so state must be re-polled until it settles.
    static func needsPoll(_ connections: [VPNConnection]) -> Bool {
        connections.contains { $0.status == .connecting || $0.status == .disconnecting }
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
        let disconnectClosure: (String) -> Void = { [weak self] in self?.disconnect($0) }
        for id in launched where core.rules[id] != nil {
            core.appLaunched(id, connect: connectAuto, disconnect: disconnectClosure)
        }
        for id in quit where core.rules[id] != nil {
            core.appTerminated(id, connect: connectAuto, disconnect: disconnectClosure)
        }
    }

    // MARK: - Transport

    private struct NamePayload: Codable { let name: String }
    private struct StatePayload: Codable {
        let connections: [VPNConnection]
        let autoConnected: [String]
        let defaultName: String?
    }

    private func wireTransport() {
        localTransport.setHandler { [weak self] cmd in
            guard let self else { return Data() }
            switch cmd.name {
            case "toggle":
                self.toggleDefault()
            case "connect":
                if let payload = try? JSONDecoder().decode(NamePayload.self, from: cmd.payload) {
                    self.connect(payload.name)
                }
            case "disconnect":
                if let payload = try? JSONDecoder().decode(NamePayload.self, from: cmd.payload) {
                    self.disconnect(payload.name)
                }
            case "refresh":
                self.refresh()
            case "reloadRules":
                self.reloadRules()
            default:
                break
            }
            return Data()
        }
    }

    private func emitState() {
        let payload = StatePayload(connections: connections,
                                    autoConnected: autoConnected.sorted(),
                                    defaultName: defaultConnection?.name)
        if let data = try? JSONEncoder().encode(payload) {
            localTransport.emit(EngineEvent(name: "state", payload: data))
        }
    }
}
