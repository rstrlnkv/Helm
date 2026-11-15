// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import XCTest
@testable import Module_VPN_Engine

/// Reading the states the engine emits, the ways a test needs it. Shared
/// rather than private to whichever file needed it first: the sentinel below is
/// the difference between a count and a race, and a second copy of it is a
/// second chance to leave the sentinel out.
///
/// Every state the news carried while `work` ran: the subscriber registers
/// before the work and reads until it meets a state the test itself said after
/// it. Structure, not a size a race can satisfy — with `.inline` work
/// everything before the sentinel is already buffered when the count starts,
/// and the read ends rather than waiting on a stream that never finishes,
/// which would hang the suite instead of failing it.
///
/// The sentinel is a payload naming a fresh token in `autoConnected`, said in a
/// slot of its own, because the news replays the last value **of each slot** to
/// a new subscriber — a fixed token would be replayed to the next drain on the
/// same news and end it before it had read anything. An older drain's sentinel
/// is replayed too, and is skipped by its prefix.
let sentinelPrefix = "test.sentinel."

func isSentinel(_ state: VPNEngine.StatePayload) -> Bool {
    state.autoConnected.first?.hasPrefix(sentinelPrefix) == true
}

func stateEvents(on news: EngineNews<VPNEngine.StatePayload>,
                 during work: () -> Void = {}) async -> [VPNEngine.StatePayload] {
    let events = news.stream()
    work()
    let token = sentinelPrefix + UUID().uuidString
    news.say(VPNEngine.StatePayload(connections: [], autoConnected: [token], lastAutomation: nil),
             slot: token)
    var seen: [VPNEngine.StatePayload] = []
    for await state in events {
        if state.autoConnected == [token] { break }
        if !isSentinel(state) { seen.append(state) }
    }
    return seen
}

/// The state a page opened now would draw: the news replays the last value of
/// each slot to every new subscriber, which is what a subscriber that comes after
/// the engine has spoken receives. Nil is «the engine has said nothing».
func lastState(on news: EngineNews<VPNEngine.StatePayload>) async -> VPNEngine.StatePayload? {
    await stateEvents(on: news).last
}

/// Watches the emitted states until a payload the test is waiting for arrives, and says so
/// through an expectation.
///
/// For the answers that reach the page **when they arrive** rather than by the
/// time the call returns — the exit check and the speed run both leave the
/// module's queue. The alternative is a fixed number of yields, which asserts on
/// whichever half of the work had finished. The caller cancels the returned task.
func watchState(_ news: EngineNews<VPNEngine.StatePayload>,
                until matches: @escaping @Sendable (VPNEngine.StatePayload) -> Bool,
                then arrived: XCTestExpectation) -> Task<Void, Never> {
    let events = news.stream()
    return Task {
        for await payload in events where !isSentinel(payload) && matches(payload) {
            arrived.fulfill()
            return
        }
    }
}

/// Kick the engine and **wait for the state that shows it happened.**
///
/// `VPNEngine.refresh()` puts the work on a queue and returns at once, so a test
/// that reads the news straight afterwards is reading whatever had already
/// arrived — usually the state before the one it asked for. Worse, a test that
/// then changes the runner's answers is racing the refresh it just started: the
/// read may pick up the *next* fixture, and the step it meant to exercise never
/// happens at all.
///
/// The subscription is taken **before** the engine is kicked, because the
/// news replays only the last value per slot: subscribing afterwards can
/// miss the state and wait for ever for one that has already gone by.
///
/// Answers whether the state arrived; the caller reads the last state itself
/// afterwards, which is the same value by then.
@discardableResult
func refreshed(_ engine: VPNEngine, on news: EngineNews<VPNEngine.StatePayload>,
               timeout: TimeInterval = 5,
               until matches: @escaping @Sendable (VPNEngine.StatePayload) -> Bool)
    async -> Bool {
    await stepped(on: news, timeout: timeout, until: matches) { engine.refresh() }
}

/// The same wait around any act that makes the engine speak.
@discardableResult
func stepped(on news: EngineNews<VPNEngine.StatePayload>, timeout: TimeInterval = 5,
             until matches: @escaping @Sendable (VPNEngine.StatePayload) -> Bool,
             _ act: () -> Void) async -> Bool {
    let events = news.stream()
    let watcher = Task { () -> Bool in
        for await payload in events where !isSentinel(payload) {
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
