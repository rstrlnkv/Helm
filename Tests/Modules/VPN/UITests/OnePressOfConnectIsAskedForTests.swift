// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import SwiftUI
import AppKit
import HelmContract
import HelmRuntime
import HelmUI
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **The state Helm declined to ask about, said on the screen.**
///
/// An automatic connect may not open the System keychain, and an empty credential
/// cache therefore means a rule cannot raise its tunnel at all. The engine knows
/// (`VPNSecretBook`); until this landed the only account of it was a line in
/// `~/Library/Logs/Helm/helm.log`, which is the outcome CLAUDE.md forbids — the app
/// silently not doing the thing it was asked.
///
/// **One surface, and it used to be two.** The banner spoke for the configurations
/// no rule covered and each rule's own row spoke for the rest, which is why
/// `VPNRules.unspokenFor` existed. The rules live behind a door on their card now,
/// so that row is invisible until somebody opens a popover — and a configuration
/// that cannot raise its tunnel said so nowhere at all. Measured here as «the page
/// grows a news card, once per locked configuration».
@MainActor
final class OnePressOfConnectIsAskedForTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    // MARK: - The wire reaches the model

    func testTheModelPublishesWhatTheEngineCouldNotRead() {
        let transport = LocalTransport()
        let vm = VPNViewModel(transport: transport)
        var payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: "Office", status: .disconnected,
                                        kind: "IPSec")],
            autoConnected: [], defaultName: "Office", lastAutomation: nil)
        payload.secretsBehindAPrompt = ["Office"]
        transport.emit(EngineEvent(name: VPNEvent.state.rawValue,
                                   payload: try! JSONEncoder().encode(payload)))
        pump { !vm.connections.isEmpty }

        XCTAssertEqual(vm.secretsBehindAPrompt, ["Office"],
                       "the engine published it and the page could not see it")
    }

    // MARK: - The page says it

    /// **The news card appears, and it is what the sentence is drawn in.**
    ///
    /// **The page's one section is its news, so with nothing to say it draws no
    /// card at all** — every setting is on a card or behind its doors. Counted in
    /// AppKit frames rather than pixels, so «the page grew a card» is a number and
    /// not an inference from colour, and the quiet page is the control: a page that
    /// had stopped drawing the sentence fails here.
    func testALockedConfigurationPutsANewsCardOnThePage() {
        XCTAssertEqual(sectionCards(mount(page([]))).count, 0,
                       "with nothing to say the page draws no section card")
        XCTAssertEqual(sectionCards(mount(page(["One"]))).count, 1,
                       "a locked configuration drew no news card")
    }

    /// **And it says it however many rules point at that configuration.** This is
    /// the regression the door cost: `unspokenFor` removed a configuration a rule
    /// covered, on the strength of a row 230 pt below — a row that is inside a
    /// popover now. Both fixtures have a rule; one points at the locked
    /// configuration and one somewhere else, and the sentence has to survive both.
    func testTheRuleBehindTheDoorDoesNotSilenceThePage() {
        for pointedAt in ["One", "Other"] {
            let quiet = newsCardHeight(locked: [], ruleFor: pointedAt)
            let stuck = newsCardHeight(locked: ["One"], ruleFor: pointedAt)
            XCTAssertGreaterThan(stuck, quiet,
                                 "with the rule pointing at «\(pointedAt)» the page grew "
                                 + "\(stuck) against \(quiet): the sentence is nowhere")
        }
    }

    /// One sentence per configuration, and the increment says so: a second locked
    /// configuration adds exactly the height of the first sentence.
    ///
    /// **Both fixtures keep the rule pointing at «One».** A rule pointing anywhere
    /// else is a rule pointing at a configuration this Mac does not have, which is
    /// its own sentence in the same card — measured at 107 pt against 54 while this
    /// test was being written, and read for a moment as the page saying the locked
    /// one twice.
    func testEachLockedConfigurationIsNamedOnce() {
        let one = newsCardHeight(locked: ["One"], ruleFor: "One")
        let two = newsCardHeight(locked: ["One", "Two"], ruleFor: "One")
        XCTAssertLessThan(one, 80,
                          "one locked configuration drew \(one) pt, which is two rows: the same "
                          + "sentence twice")
        XCTAssertEqual(two - one, one, accuracy: 6,
                       "a second locked configuration added \(two - one) pt where one sentence "
                       + "is \(one): it is not named, or it is named more than once")
    }

    // MARK: - The page, and its instrument

    private func page(_ locked: [String], ruleFor vpn: String = "One") -> VPNSettingsPage {
        let transport = LocalTransport()
        // In memory, never `UserDefaults.standard`: this page writes its settings
        // through on every change.
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        // One rule, pointing at the one connection, so the section under the header
        // has a row drawn at its natural height.
        settings.setRulesJSON(VPNRules.encode([
            "com.apple.Safari": VPNAppRule(vpnName: vpn,
                                           identity: CodeIdentity(signingID: "com.apple.Safari",
                                                                  teamID: "APPLE"))]))
        let vm = VPNViewModel(transport: transport, settings: settings)
        var payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "id-One", name: "One", status: .disconnected,
                                        kind: "IPSec")],
            autoConnected: [], defaultName: nil, lastAutomation: nil)
        payload.secretsBehindAPrompt = locked
        transport.emit(EngineEvent(name: VPNEvent.state.rawValue,
                                   payload: try! JSONEncoder().encode(payload)))
        pump { !vm.connections.isEmpty }
        XCTAssertEqual(vm.connections.count, 1,
                       "the wire did not deliver: nothing below measures anything")
        XCTAssertEqual(vm.secretsBehindAPrompt, locked, "…nor the state under test")
        return VPNSettingsPage(vm: vm, store: store)
    }

    /// Turns of the main run loop until `done`, or 80 of them — and therefore a
    /// **synchronous** test: driven from an `async` body this pumps nothing, and
    /// every reading comes back as the zero-connection empty state, which passes an
    /// assertion about a banner by having no page.
    private func pump(_ done: () -> Bool) {
        for _ in 0..<80 where !done() {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private static let width: CGFloat = 845

    private func mount(_ page: VPNSettingsPage) -> MountedRender {
        // Pinned light, like every other reading in this house: `NSApp`'s
        // appearance in a test process is whatever this Mac is set to this hour.
        let render = MountedRender(page, width: Self.width, height: 1500, appearance: .aqua)
        renders.append(render)
        render.settle(60)
        return render
    }

    private func sectionCards(_ render: MountedRender) -> [NSRect] {
        Set(render.host.everyView(named: "_NSGraphicsView").map(\.frame))
            .sorted { $0.minY < $1.minY }
    }

    /// The height of everything the page has to say. **Zero is a real answer**:
    /// the news is the page's only section, so a page with nothing to say draws no
    /// card — which is what makes «it grew» a reading rather than a comparison of
    /// two heights that might both be of the wrong card.
    private func newsCardHeight(locked: [String], ruleFor vpn: String) -> CGFloat {
        sectionCards(mount(page(locked, ruleFor: vpn))).first?.height ?? 0
    }
}
