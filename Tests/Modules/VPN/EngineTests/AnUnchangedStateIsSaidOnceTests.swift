// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_VPN_Engine

/// **A poll that learned nothing is not news.**
///
/// `refreshNow` ends in an unconditional `emitState()`, and `pollUntilSettled`
/// calls `refreshNow` up to 26 times behind one connect — so a tunnel that
/// hangs put 26 identical payloads on the wire, each one re-rendering every
/// mounted page. The owner's log shows auto-connect retrying all night
/// («never reached connected after 25 polls», every ~25 s), which made this
/// the largest single source of idle re-renders in the app
/// (`HiddenPageEventChurnBenchmark` prices what each of those costs a page).
///
/// The rule is exact: only a payload **equal in every field** to the last one
/// sent is suppressed. A change of any kind — a status, a failure, a secret
/// notice — must go out, because a page that is never told cannot stop being
/// wrong (CLAUDE.md § anything that can stop being true owns a channel). What
/// is suppressed is the duplicate, never the confirmation of a change.
final class AnUnchangedStateIsSaidOnceTests: XCTestCase {

    private let uuid = "11111111-1111-1111-1111-111111111111"

    private func list(_ status: String, _ name: String = "A") -> String {
        "(\(status)) \(uuid) IPSec \"\(name)\""
    }

    private func makeSettings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn",
                                           backing: InMemoryKeyValueStore()))
    }

    /// How many `state` events the transport carried, counted through a
    /// sentinel: the subscriber registers before the work and reads until it
    /// meets an event the test itself emitted after it. Structure, not a size a
    /// race can satisfy — with `.inline` work everything before the sentinel is
    /// already buffered when the count starts.
    private func stateEvents(on transport: LocalTransport,
                             during work: () -> Void) async -> Int {
        let events = transport.events
        work()
        transport.emit(EngineEvent(name: "test.sentinel", payload: Data()))
        var count = 0
        for await event in events {
            if event.name == "test.sentinel" { break }
            if event.name == VPNEvent.state.rawValue { count += 1 }
        }
        return count
    }

    /// The owner's night, in one call: from a state the page has already seen,
    /// a connect the tool accepted whose tunnel never comes up. The poll
    /// re-reads 26 times, the list never changes — one emission in total, for
    /// the baseline; the connect and every poll after it learned nothing.
    func test_a_connect_that_never_settles_emits_its_state_once() async {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let transport = LocalTransport()
        let engine = VPNEngine(settings: makeSettings(), runner: runner,
                               apps: FakeApps(), transport: transport, work: .inline)

        let count = await stateEvents(on: transport) {
            engine.refresh()                          // the page's baseline
            engine.connect("A")                       // accepted, never settles
        }

        XCTAssertGreaterThan(runner.listReadCount, 25,
                             "precondition: the poll did run its 26 reads — without them "
                             + "this test would pass against an engine that never polls")
        XCTAssertEqual(count, 1,
                       "\(count) state events for one unchanged answer: every mounted page "
                       + "re-rendered \(count) times to learn nothing")
    }

    /// The other half, without which the first is a page that has gone silent:
    /// every real change passes, and a return to a previous state is a change.
    func test_every_change_is_emitted_and_a_return_is_a_change() async {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let transport = LocalTransport()
        let engine = VPNEngine(settings: makeSettings(), runner: runner,
                               apps: FakeApps(), transport: transport, work: .inline)

        let count = await stateEvents(on: transport) {
            engine.refresh()                          // new → emits
            engine.refresh()                          // same → silent
            runner.listOutput = list("Connected")
            engine.refresh()                          // changed → emits
            runner.listOutput = list("Disconnected")
            engine.refresh()                          // changed back → emits
        }

        XCTAssertEqual(count, 3,
                       "four refreshes over three distinct states must say exactly three "
                       + "things — a suppressed change is a page that is wrong for good, "
                       + "a repeated duplicate is the night of re-renders")
    }

    /// A refusal is a change even when the connection list is not: the payload
    /// differs in `lastFailure`, so it goes out. The dedupe compares whole
    /// payloads, and this is the field a cheaper comparison would drop first.
    func test_a_refusal_with_an_unchanged_list_is_still_emitted() async {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected", "Office")
        let transport = LocalTransport()
        let engine = VPNEngine(settings: makeSettings(), runner: runner,
                               apps: FakeApps(), transport: transport, work: .inline)

        let count = await stateEvents(on: transport) {
            engine.refresh()                          // baseline state
            runner.reply = "No service"
            engine.connect("Old office")              // list unchanged, failure new
        }

        XCTAssertEqual(count, 2,
                       "the refusal reached the wire or the page never learns the "
                       + "command it asked for was refused")
    }
}
