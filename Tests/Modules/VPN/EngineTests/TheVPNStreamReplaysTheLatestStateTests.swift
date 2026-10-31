// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_VPN_Engine

/// `VPNEngine.stream()` hands a subscriber that arrives late the state it missed,
/// then every later one in order — the forced re-emission a refused measurement
/// makes included — and gives the subscription back when the reader stops.
///
/// Defect class kept: a level-triggered state read through a stream the model
/// takes after `activate()`. The model is built when the module starts and the
/// engine has already published; a stream that replays nothing leaves the page
/// drawing an empty list until the next change, a stream that drops the forced
/// re-emission leaves a spinner nothing clears, and a subscriber never given back
/// outlives the model that made it. The engine runs its own `EngineNews`,
/// passed in, so the count of subscribers is the engine's.
@MainActor
final class TheVPNStreamReplaysTheLatestStateTests: XCTestCase {

    private func engine(_ runner: FakeRunner, news: EngineNews<VPNEngine.StatePayload>,
                        interfaces: FakeInterfaces = FakeInterfaces()) -> VPNEngine {
        VPNEngine(settings: VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                               backing: InMemoryKeyValueStore())),
                  runner: runner, apps: FakeApps(), news: news,
                  interfaces: interfaces, exit: FakeExit(), speed: FakeSpeed(), work: .inline)
    }

    private func listed(_ status: String) -> FakeRunner {
        let runner = FakeRunner()
        runner.listOutput = "(\(status)) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        return runner
    }

    /// Everything one reader was handed, in order.
    private final class Reader: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [VPNEngine.StatePayload] = []
        private(set) var task: Task<Void, Never>?
        var states: [VPNEngine.StatePayload] { lock.withLock { seen } }
        init(_ stream: AsyncStream<VPNEngine.StatePayload>) {
            task = Task { [self] in
                for await state in stream { lock.withLock { seen.append(state) } }
            }
        }
    }

    func testASubscriberAfterTheEngineSpokeIsHandedTheStateItMissed() async {
        let engine = engine(listed("Connected"), news: EngineNews())
        engine.refresh()

        let reader = Reader(engine.stream())
        await waitUntil("the missed state is replayed") { !reader.states.isEmpty }
        XCTAssertEqual(reader.states.first?.connections.map(\.name), ["A"],
                       "the late subscriber was not told what the engine had read")
        reader.task?.cancel()
    }

    func testLaterStatesArriveInOrder() async {
        let runner = listed("Disconnected")
        let engine = engine(runner, news: EngineNews())
        engine.refresh()
        let reader = Reader(engine.stream())
        await waitUntil("the replay") { !reader.states.isEmpty }

        runner.listOutput = "(Connected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        engine.refresh()
        await waitUntil("the state after the tunnel came up") {
            reader.states.last?.connections.first?.status == .connected
        }

        let statuses = reader.states.compactMap { $0.connections.first?.status }
        XCTAssertEqual(statuses.first, .disconnected, "the replay did not come first")
        XCTAssertEqual(statuses.last, .connected, "the later state did not come after it")
        if let up = statuses.firstIndex(of: .connected) {
            XCTAssertFalse(statuses[up...].contains(.disconnected),
                           "an older state arrived after a newer one: \(statuses)")
        }
        reader.task?.cancel()
    }

    /// A refused measurement moves no field of the payload, so the dedup would
    /// withhold it; the engine forces it, and the stream must not add a dedup of
    /// its own.
    func testTheForcedReEmissionOfARefusedMeasurementArrives() async {
        let engine = engine(listed("Connected"), news: EngineNews())
        engine.refresh()
        let reader = Reader(engine.stream())
        await waitUntil("the replay") { !reader.states.isEmpty }
        let before = reader.states.count

        engine.measureSpeed("a tunnel nobody has")

        await waitUntil("the refusal is published again") { reader.states.count > before }
        XCTAssertEqual(reader.states.last, reader.states.first,
                       "precondition: the refusal moved no field, so only force delivers it")
        reader.task?.cancel()
    }

    func testEndingTheIterationGivesTheSubscriberBack() async {
        let news = EngineNews<VPNEngine.StatePayload>()
        let engine = engine(FakeRunner(), news: news)
        XCTAssertEqual(news.subscriberCount, 0, "precondition: nobody has subscribed")

        let reader = Reader(engine.stream())
        await waitUntil("the stream registers") { news.subscriberCount == 1 }
        reader.task?.cancel()
        await waitUntil("the stream is given back") { news.subscriberCount == 0 }
    }
}
