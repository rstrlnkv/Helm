// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// The one thing between a tunnel that hangs and `scutil` being run for ever.
///
/// A connect schedules `pollUntilSettled`, which re-reads the list while
/// anything is transitioning and stops at `maxPollAttempts`. Nothing tested any
/// of it, and it could not be tested: `FakeRunner.listOutput` was a single
/// constant, so the tool's answer never changed as a consequence of the command
/// it had just been given, and «the tunnel came up on the third read» — which is
/// what the real tool does, and the only reason the poll exists — was a state no
/// test could write down. So the bound had no guard, and a `connecting` that
/// never resolves is exactly the state this module already knows can last for
/// good: `VPNCardAction` has a comment about it.
///
/// `listScript` is that repair, and these two tests are what it buys.
final class ATunnelThatHangsIsNotPolledForEverTests: XCTestCase {

    private let uuid = "11111111-1111-1111-1111-111111111111"

    private func list(_ status: String) -> String { "(\(status)) \(uuid) IPSec \"A\"" }

    /// `.inline`, like every other engine test here: the work queue runs the
    /// poll's body straight through instead of after 0.7 s, so the whole poll
    /// happens inside `connect` and its length is a number this test can read.
    private func engine(_ runner: FakeRunner) -> VPNEngine {
        VPNEngine(settings: VPNSettings(store: NamespacedStore(
                    namespace: "vpn", backing: InMemoryKeyValueStore())),
                  runner: runner, apps: FakeApps(), work: .inline)
    }

    /// A server that never answers: the list says `Connecting` for ever.
    ///
    /// The bound is asserted as a bound rather than as its exact value — 25 is a
    /// judgement about IKEv2 handshakes and may be re-judged — but it is asserted
    /// from **both** sides, because a poll that gives up at once is the defect
    /// this loop replaced (a single 0.6 s re-read left the spinner stuck) and a
    /// poll with no ceiling runs a subprocess until the app quits.
    func testAConnectingTunnelIsPolledAndThenGivenUpOn() {
        let runner = FakeRunner()
        runner.listScript = [list("Connecting")]
        let e = engine(runner)

        e.connect("A")

        XCTAssertGreaterThan(runner.listReadCount, 2,
                             "a tunnel still coming up was not re-read at all: the card would "
                             + "sit on «Connecting…» until something else redrew it")
        XCTAssertLessThan(runner.listReadCount, 40,
                          "\(runner.listReadCount) reads of `scutil --nc list` for one connect — "
                          + "a tunnel that never settles must not run a subprocess for ever")
        XCTAssertEqual(e.status("A"), .connecting,
                       "precondition: the tool really did keep saying Connecting")
    }

    /// The control: once the poll has started it does run to the end, and stops
    /// there rather than using up its ceiling.
    func testAPollThatHasStartedFollowsATunnelUpAndThenStops() {
        let runner = FakeRunner()
        runner.listScript = [list("Connecting"), list("Connecting"), list("Connected")]
        let e = engine(runner)

        e.connect("A")

        XCTAssertEqual(e.status("A"), .connected, "the poll did not follow the tunnel up")
        XCTAssertLessThan(runner.listReadCount, 8,
                          "the tunnel settled and the engine kept reading: "
                          + "\(runner.listReadCount) reads")
    }

    /// **And the sequence the real tool actually produces, which ends the poll on
    /// the first attempt.**
    ///
    /// `refreshNow`'s own comment says it: «the refresh that follows a connect
    /// usually still reports the old status». `pollUntilSettled` reads that first
    /// answer, asks `needsPoll` — is anything *transitioning* — is told no,
    /// because `Disconnected` is not a transition, and stops. So the 25 attempts
    /// that `maxPollAttempts`' comment says «cover slow IKEv2 handshakes» are
    /// never spent on one: a slow handshake is precisely the case that reads
    /// `Disconnected` first.
    ///
    /// What is left holding the page up to date is `DynamicStoreNetworkWatch` —
    /// and its own failure path logs «no network-state session; the connection
    /// list will only be re-read when Helm is asked». On that Mac the card stays
    /// on «Disconnected» after a connect that worked, which is the same wrong
    /// answer, in the same place, that the watcher was added to fix.
    ///
    /// Left red for the engineer: the exit condition wants to be «has it settled
    /// into what was asked for», not «is something moving right now».
    func testAConnectIsFollowedUpEvenWhenTheToolHasNotCaughtUpYet() {
        let runner = FakeRunner()
        runner.listScript = [list("Disconnected"),   // the tool has not caught up yet
                             list("Connecting"),
                             list("Connected")]
        let e = engine(runner)

        e.connect("A")

        XCTAssertTrue(runner.issued.contains(["--nc", "start", "A"]),
                      "precondition: the connect was issued")
        XCTAssertEqual(e.status("A"), .connected,
                       "the poll gave up after \(runner.listReadCount) read(s) because the tool "
                       + "was still saying Disconnected — which is what it says while a tunnel "
                       + "comes up, and the only state the poll exists for")
    }

    /// **This one cannot fail today, and it is here anyway — as a constraint on
    /// the repair above, not as evidence about the present.**
    ///
    /// It passes because the poll stops after one read *whatever* happened, which
    /// is the defect the test above is about. Proven so: it survived both
    /// mutations that turned the other three red — the ceiling raised to 500 and
    /// `needsPoll` forced to `false`. What it is for is the obvious wrong fix: an
    /// exit condition of «keep reading until the tunnel is up» would spend all 25
    /// attempts and 17 s of subprocesses on a name `scutil` has already said does
    /// not exist. The precondition below *is* live, so this cannot rot into
    /// passing on a module that has stopped reading refusals at all.
    func testARefusedConnectIsNotPolledAsIfItHadStarted() {
        let runner = FakeRunner()
        runner.listScript = [list("Disconnected")]
        runner.replies["Old office"] = "No service"
        let e = engine(runner)

        e.connect("Old office")

        XCTAssertEqual(e.lastFailure?.reason, .noSuchService, "precondition: it was refused")
        XCTAssertLessThan(runner.listReadCount, 4,
                          "\(runner.listReadCount) polls waiting for a tunnel `scutil` said "
                          + "does not exist")
    }
}
