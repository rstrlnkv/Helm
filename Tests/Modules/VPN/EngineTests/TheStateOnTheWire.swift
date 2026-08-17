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
