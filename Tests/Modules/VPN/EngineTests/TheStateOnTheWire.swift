// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import XCTest
@testable import Module_VPN_Engine

/// Reading what the engine told the page, the two ways a test needs it. Shared
/// rather than private to whichever file needed it first: the sentinel below is
/// the difference between a count and a race, and a second copy of it is a
/// second chance to leave the sentinel out.
///
/// Every `state` event the transport carried while `work` ran: the subscriber
/// registers before the work and reads until it meets an event the test itself
/// emitted after it. Structure, not a size a race can satisfy — with `.inline`
/// work everything before the sentinel is already buffered when the count
/// starts, and the read ends rather than waiting on a stream that never
/// finishes, which would hang the suite instead of failing it.
///
/// The sentinel carries a fresh name every time, because the transport replays
/// the last event **of each name** to a new subscriber — a fixed name would be
/// replayed to the next drain on the same transport and end it before it had
/// read anything.
func stateEvents(on transport: LocalTransport,
                 during work: () -> Void = {}) async -> [VPNEngine.StatePayload?] {
    let events = transport.events
    work()
    let end = EngineEvent(name: "test.sentinel.\(UUID().uuidString)", payload: Data())
    transport.emit(end)
    var seen: [VPNEngine.StatePayload?] = []
    for await event in events {
        if event.name == end.name { break }
        if event.name == VPNEvent.state.rawValue {
            seen.append(try? JSONDecoder().decode(VPNEngine.StatePayload.self,
                                                  from: event.payload))
        }
    }
    return seen
}

/// The state a page opened now would draw: the transport replays the last event
/// of each name to every new subscriber, which is what a view model built after
/// the engine has already spoken receives. Nil is «the engine has said nothing».
func lastState(on transport: LocalTransport) async -> VPNEngine.StatePayload? {
    await stateEvents(on: transport).last ?? nil
}

/// Watches the wire until a payload the test is waiting for arrives, and says so
/// through an expectation.
///
/// For the answers that reach the page **when they arrive** rather than by the
/// time the call returns — the exit check and the speed run both leave the
/// module's queue. The alternative is a fixed number of yields, which asserts on
/// whichever half of the work had finished. The caller cancels the returned task.
func watchState(_ transport: LocalTransport,
                until matches: @escaping @Sendable (VPNEngine.StatePayload) -> Bool,
                then arrived: XCTestExpectation) -> Task<Void, Never> {
    let events = transport.events
    return Task {
        for await event in events where event.name == VPNEvent.state.rawValue {
            guard let payload = try? JSONDecoder().decode(VPNEngine.StatePayload.self,
                                                          from: event.payload),
                  matches(payload) else { continue }
            arrived.fulfill()
            return
        }
    }
}

/// Kick the engine and **wait for the state that shows it happened.**
///
/// `VPNEngine.refresh()` puts the work on a queue and returns at once, so a test
/// that reads the wire straight afterwards is reading whatever had already
/// arrived — usually the state before the one it asked for. Worse, a test that
/// then changes the runner's answers is racing the refresh it just started: the
/// read may pick up the *next* fixture, and the step it meant to exercise never
/// happens at all.
///
/// The subscription is taken **before** the engine is kicked, because the
/// transport replays only the last event per name: subscribing afterwards can
/// miss the state and wait for ever for one that has already gone by.
///
/// Answers whether the state arrived. It is a `Bool` rather than the payload
/// because `StatePayload` is not `Sendable` and must not cross out of the
/// watching task; the caller reads the wire itself afterwards, which is the
/// same value by then.
@discardableResult
func refreshed(_ engine: VPNEngine, on transport: LocalTransport,
               timeout: TimeInterval = 5,
               until matches: @escaping @Sendable (VPNEngine.StatePayload) -> Bool)
    async -> Bool {
    await stepped(on: transport, timeout: timeout, until: matches) { engine.refresh() }
}

/// The same wait around any act that makes the engine speak.
@discardableResult
func stepped(on transport: LocalTransport, timeout: TimeInterval = 5,
             until matches: @escaping @Sendable (VPNEngine.StatePayload) -> Bool,
             _ act: () -> Void) async -> Bool {
    let events = transport.events
    let watcher = Task { () -> Bool in
        for await event in events where event.name == VPNEvent.state.rawValue {
            guard let payload = try? JSONDecoder().decode(VPNEngine.StatePayload.self,
                                                          from: event.payload) else { continue }
            if matches(payload) { return true }
        }
        return false
    }
    act()
    let deadline = Task {
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        watcher.cancel()
    }
    let arrived = await watcher.value
    deadline.cancel()
    return arrived
}
