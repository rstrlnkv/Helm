// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// Stands for the engine on the model's side of `VPNWork`: the port's members
/// and nothing the engine has beyond them.
///
/// A call is written down by its member's name, a press by its verb (`calls`);
/// `say(_:)` is what the engine would emit, and is replayed to a stream taken afterwards, first — the
/// engine's own stream does the same. A stream the consumer let go of is counted
/// (`finishedStreams`), so «the loop was cancelled» is read from the work and not
/// assumed from the model.
final class FakeVPNWork: VPNWork, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var latest: VPNEngine.StatePayload?
    private var live: [UUID: AsyncStream<VPNEngine.StatePayload>.Continuation] = [:]
    private var finished = 0

    /// Every call, in order: `stream`, `refresh`, `connect <name>`,
    /// `disconnect <name>`, `measureSpeed <name>`, `reloadRules`.
    var calls: [String] { lock.withLock { recorded } }
    var finishedStreams: Int { lock.withLock { finished } }
    var subscribers: Int { lock.withLock { live.count } }

    /// What the engine says: kept as the latest, and yielded to every open stream.
    func say(_ payload: VPNEngine.StatePayload) {
        let open = lock.withLock { () -> [AsyncStream<VPNEngine.StatePayload>.Continuation] in
            latest = payload
            return Array(live.values)
        }
        for continuation in open { continuation.yield(payload) }
    }

    func stream() -> AsyncStream<VPNEngine.StatePayload> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock {
                recorded.append("stream")
                live[id] = continuation
                if let latest { continuation.yield(latest) }
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.live[id] = nil; self?.finished += 1 }
            }
        }
    }

    func refresh() { note("refresh") }
    func press(_ verb: VPNVerb, on name: String) { note("\(verb.rawValue) \(name)") }
    func measureSpeed(_ name: String) { note("measureSpeed \(name)") }
    func reloadRules() { note("reloadRules") }

    private func note(_ call: String) { lock.withLock { recorded.append(call) } }
}
