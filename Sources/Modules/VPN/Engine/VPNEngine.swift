// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime

/// Orchestrates VPN connect/disconnect/toggle (via `scutil --nc`) and per-app
/// auto-connect (VPNAutoConnectCore) against the injected ports. `activate()`/
/// `deactivate()` are the MODULE lifecycle (host enables/disables the module);
/// they also start/stop the auto-connect app observation.
public final class VPNEngine: ModuleEngine, @unchecked Sendable {
    private let settings: VPNSettings
    private let runner: VPNRunnerPort
    private let credentials: VPNCredentialsPort?
    private let apps: AppObserverPort
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    public private(set) var connections: [VPNConnection] = []
    public private(set) var autoConnected: Set<String> = []

    private var core = VPNAutoConnectCore(rules: [:])
    private var knownBundleIDs: Set<String> = []
    private var running = false

    public init(settings: VPNSettings,
                runner: VPNRunnerPort,
                credentials: VPNCredentialsPort? = nil,
                apps: AppObserverPort,
                transport: LocalTransport = LocalTransport()) {
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
        reloadRules()
        knownBundleIDs = apps.runningBundleIDs()
        for id in knownBundleIDs {
            core.appLaunched(id,
                              connect: { [weak self] in self?.connect($0, auto: true) },
                              disconnect: { _ in })
        }
        apps.startObserving { [weak self] in self?.appsChanged() }
    }

    public func deactivate() {
        running = false
    }

    // MARK: - VPN control

    public func refresh() {
        connections = VPNListParser.parseList(runner.run(["--nc", "list"]))
        emitState()
    }

    public var defaultConnection: VPNConnection? {
        if let live = connections.first(where: { $0.status == .connected || $0.status == .connecting }) {
            return live
        }
        return VPNListParser.defaultConnection(from: connections, lastUsedName: settings.lastUsedName)
    }

    public func toggleDefault() {
        refresh()
        guard let target = defaultConnection else { return }
        settings.setLastUsed(target.name)
        if target.status == .connected || target.status == .connecting {
            disconnect(target.name)
        } else {
            connect(target.name)
        }
    }

    public func connect(_ name: String, auto: Bool = false) {
        HelmLog.shared.info("vpn", "connect \(Redact.vpn(name))\(auto ? " (auto)" : "")")
        if auto { autoConnected.insert(name) }
        var args = ["--nc", "start", name]
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
        HelmLog.shared.info("vpn", "disconnect \(Redact.vpn(name))")
        autoConnected.remove(name)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            self.refresh()
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
        refresh()
        core.rules = VPNRules.valid(VPNRules.decode(settings.rulesJSON), against: connections)
    }

    private func appsChanged() {
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
