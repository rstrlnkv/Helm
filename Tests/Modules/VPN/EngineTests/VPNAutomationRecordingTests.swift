// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_VPN_Engine

/// The whole point of the indicator is the distinction between Helm's own work
/// and the person's: a ring that spins for a button they just pressed tells
/// them nothing they did not already know. These tests assert on the recorded
/// value itself — name, kind and the moment — rather than on "something
/// happened", because the failure this guards against is a recording that fires
/// for everything.
final class VPNAutomationRecordingTests: XCTestCase {

    private let clock = TestClock()

    private var at: Date { clock.now }
    private let uuid = "11111111-1111-1111-1111-111111111111"

    private func list(_ status: String) -> String { "(\(status)) \(uuid) IPSec \"A\"" }

    private func makeEngine(_ runner: FakeRunner,
                            apps: FakeApps = FakeApps.trustingA(),
                            settings: VPNSettings? = nil) -> VPNEngine {
        let clock = self.clock
        return VPNEngine(settings: settings ?? makeSettings(),
                         runner: runner,
                         apps: apps,
                         interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                         now: { clock.now },
                         work: .inline)
    }

    private func makeSettings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore()))
    }

    // MARK: - Helm's own work

    func test_a_connect_helm_made_itself_is_recorded_with_its_name_and_kind() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let engine = makeEngine(runner)

        engine.connect("A", auto: true)

        XCTAssertEqual(engine.lastAutomation,
                       VPNAutomation(at: at, name: "A", kind: .connected),
                       "a rule raised this tunnel; the ring has nothing to spin for otherwise")
    }

    /// The clock is injected so the recorded moment is a fact of the test rather
    /// than of the machine — `spinPhase` measures from it.
    func test_the_recorded_moment_comes_from_the_injected_clock() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let engine = makeEngine(runner)

        engine.connect("A", auto: true)

        XCTAssertEqual(engine.lastAutomation?.at, at)
    }

    // MARK: - Work that changed nothing

    /// The case measured on a real machine: the rule's app was already running,
    /// so `activate()` replayed `appLaunched` at every launch of Helm, and the
    /// tunnel it asks for was already up. `scutil --nc start` is a no-op there —
    /// the ring spun and named a VPN nobody had touched, every single launch.
    /// An indicator that fires for that indicates nothing.
    func test_a_rule_asking_for_a_tunnel_already_up_records_nothing() {
        let runner = FakeRunner()
        runner.listOutput = list("Connected")
        let engine = makeEngine(runner, apps: alreadyRunning(), settings: ruleForA())

        engine.activate()

        XCTAssertTrue(runner.issued.contains(["--nc", "start", "A"]),
                      "the rule has to have fired at all for the assertion below to mean anything")
        XCTAssertNil(engine.lastAutomation,
                     "Helm asked for a tunnel that was already up, so Helm changed nothing")
    }

    /// The guard against buying the test above by never recording on this path:
    /// the same replay, with the tunnel actually down, is a real firing.
    func test_the_same_rule_asking_for_a_tunnel_that_is_down_is_recorded() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let engine = makeEngine(runner, apps: alreadyRunning(), settings: ruleForA())

        engine.activate()

        XCTAssertEqual(engine.lastAutomation,
                       VPNAutomation(at: at, name: "A", kind: .connected))
    }

    /// Already up is still Helm's to take down when the app quits: the quit rule
    /// reads `_autoConnected`, and declining to *announce* must not be read as
    /// declining to own.
    func test_a_tunnel_already_up_is_still_recorded_as_helms_own() {
        let runner = FakeRunner()
        runner.listOutput = list("Connected")
        let engine = makeEngine(runner, apps: alreadyRunning(), settings: ruleForA())

        engine.activate()

        XCTAssertTrue(engine.autoConnected.contains("A"))
    }

    private func alreadyRunning() -> FakeApps {
        let apps = FakeApps.trustingA()
        apps.bundleIDs = ["com.a"]
        return apps
    }

    private func ruleForA() -> VPNSettings {
        let settings = makeSettings()
        settings.setRulesJSON(
            ruleJSONForA)
        return settings
    }

    // MARK: - The person's work

    func test_a_connect_the_person_asked_for_is_not_recorded() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let engine = makeEngine(runner)

        engine.connect("A")

        XCTAssertNil(engine.lastAutomation,
                     "the person pressed the button; announcing it back to them says nothing")
    }

    func test_a_disconnect_the_person_asked_for_is_not_recorded() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let engine = makeEngine(runner)
        // Something to overwrite: nil afterwards then means "nothing was
        // written", not "nothing was ever written".
        engine.connect("A", auto: true)
        engine.clearLastAutomationForTesting()

        engine.disconnect("A")

        XCTAssertNil(engine.lastAutomation,
                     "a disconnect asked for from the panel is the person's, not Helm's")
    }

    /// The guard against buying the tests above by recording every drop: a
    /// tunnel the person raised themselves is not Helm's to announce when it
    /// goes, however it goes.
    func test_a_tunnel_the_person_raised_that_drops_is_not_recorded() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let engine = makeEngine(runner)
        engine.connect("A")

        runner.listOutput = list("Connected")
        engine.refresh()
        runner.listOutput = list("Disconnected")
        engine.refresh()

        XCTAssertNil(engine.lastAutomation,
                     "Helm never raised this one, so its going is not Helm's news")
    }

    // MARK: - The drop path

    /// A tunnel Helm raised that came up and then went — the network went, or
    /// somebody stopped it in System Settings — leaves `_autoConnected` on the
    /// refresh path. That is a firing: what Helm arranged is no longer true.
    ///
    /// **`.dropped`, and it used to be `.disconnected`** — the same case a quit
    /// rule produces. The two shared a kind, so they shared a set of words and
    /// one volume: somebody who wanted their rules to fire in silence was also
    /// asking not to be told when the tunnel fell over underneath them.
    func test_a_tunnel_helm_raised_that_drops_on_its_own_is_recorded_as_dropped() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let engine = makeEngine(runner)
        engine.connect("A", auto: true)
        runner.listOutput = list("Connected")
        engine.refresh()
        engine.clearLastAutomationForTesting()

        runner.listOutput = list("Disconnected")
        engine.refresh()
        // **Held for the settle window first.** A tunnel seen down once is a
        // re-handshake until the clock says otherwise (`VPNDropSettle`), so the
        // recording is stamped at the moment the loss is *established* rather
        // than at the moment it was first seen.
        XCTAssertNil(engine.lastAutomation,
                     "the drop was recorded on the first read that saw the tunnel down")
        clock.advance(VPNDropSettle.window)
        engine.refresh()

        XCTAssertEqual(engine.lastAutomation,
                       VPNAutomation(at: at, name: "A", kind: .dropped),
                       "a tunnel that fell over was recorded as a rule taking it down")
        XCTAssertFalse(engine.autoConnected.contains("A"),
                       "the recording must follow the same drop the bookkeeping made")
    }

    /// The connect Helm has just issued has not come up yet on the first refresh
    /// — the case `_cameUp` exists for. Nothing dropped, so nothing is recorded.
    func test_a_connect_that_has_not_come_up_yet_records_no_disconnect() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let engine = makeEngine(runner)
        engine.connect("A", auto: true)
        engine.clearLastAutomationForTesting()

        engine.refresh()
        engine.refresh()

        XCTAssertNil(engine.lastAutomation,
                     "a tunnel that has not answered yet has not dropped")
    }

    /// The mirror of the launch case: a teardown that changes nothing is not
    /// news either. The rule quits, Helm asks for a stop, and the tunnel was
    /// already down — `scutil --nc stop` is a no-op and there is nothing to
    /// announce. Without this the ring spins for a disconnection that had
    /// already happened, which is the same lie as announcing one that never did.
    func test_a_teardown_of_a_tunnel_that_was_already_down_is_not_recorded() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let settings = makeSettings()
        settings.setRulesJSON(
            ruleJSONForA)
        let apps = FakeApps.trustingA()
        let engine = makeEngine(runner, apps: apps, settings: settings)

        engine.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()
        engine.refresh()                    // it never came up
        engine.clearLastAutomationForTesting()
        apps.bundleIDs = []
        apps.fire()                         // the rule tears down anyway

        XCTAssertNil(engine.lastAutomation,
                     "a teardown of a tunnel that was already down was announced as a "
                     + "disconnection the user never had")
    }

    /// The rule's own teardown: the app that raised the tunnel quits and Helm
    /// takes it down. Helm did that, so it is a firing — and it takes the same
    /// route through `disconnect` as the panel button, which is not.
    func test_a_teardown_a_rule_performed_is_recorded_as_disconnected() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let settings = makeSettings()
        settings.setRulesJSON(
            ruleJSONForA)
        let apps = FakeApps.trustingA()
        let engine = makeEngine(runner, apps: apps, settings: settings)

        engine.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()
        // The tunnel Helm just asked for comes up. This is the only state a
        // teardown can actually begin from — `appTerminated` takes down nothing
        // Helm did not raise this session — and holding the fake at
        // Disconnected here arranged a world the code cannot reach.
        runner.listOutput = list("Connected")
        engine.refresh()
        engine.clearLastAutomationForTesting()
        apps.bundleIDs = []
        apps.fire()

        XCTAssertTrue(runner.issued.contains(["--nc", "stop", "A"]),
                      "the rule has to have fired at all for the recording to mean anything")
        XCTAssertEqual(engine.lastAutomation,
                       VPNAutomation(at: at, name: "A", kind: .disconnected))
    }

    // MARK: - What the page is told

    /// Decoded from an event the engine actually emitted, not from the encoder:
    /// what the page reads is the event.
    func test_the_emitted_state_event_carries_the_last_automation() async {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let engine = makeEngine(runner)

        engine.connect("A", auto: true)

        var payload: VPNEngine.StatePayload?
        for await event in engine.transport.events where event.name == "state" {
            payload = try? JSONDecoder().decode(VPNEngine.StatePayload.self, from: event.payload)
            break
        }
        XCTAssertEqual(payload?.lastAutomation,
                       VPNAutomation(at: at, name: "A", kind: .connected))
    }

    /// A state event from a build that predates the field still decodes — the
    /// page and the engine are versioned together in one process today, and the
    /// replayed last event outlives neither, but a payload that throws takes the
    /// whole page's state down rather than one field of it.
    func test_a_state_payload_without_the_field_still_decodes() throws {
        let legacy = Data("""
        {"connections":[],"autoConnected":[],"defaultName":null}
        """.utf8)

        let payload = try JSONDecoder().decode(VPNEngine.StatePayload.self, from: legacy)

        XCTAssertNil(payload.lastAutomation)
    }
}
