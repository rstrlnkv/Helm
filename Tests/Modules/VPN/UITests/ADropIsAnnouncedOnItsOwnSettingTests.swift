// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmContract
import HelmRuntime
import HelmUI
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The drop's own setting reaches the banner.
///
/// Two settings that cannot both be read are one setting with a second name.
/// This drives the real path — a state payload carrying a firing, through
/// `handle`, through `announce` — because that is where the mode is chosen, and
/// a test of `VPNSettings` alone would pass with the view model still reading
/// the rules' mode for everything.
@MainActor
final class ADropIsAnnouncedOnItsOwnSettingTests: XCTestCase {

    /// Fires one automation of `kind` at a model whose two modes are set apart,
    /// and answers what the person was actually shown.
    private func announce(kind: VPNAutomation.Kind,
                          rules: VPNNotice, drop: VPNNotice) async
        -> (banner: [(String, String)], label: String?) {
        let transport = LocalTransport()
        let descriptor = VPNDescriptor()
        let host = ModuleViewModel(transport: transport)
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        settings.setNotice(rules)
        settings.setDropNotice(drop)
        let port = FakeAutomationNotice(state: .authorized)
        let model = VPNViewModel(transport: transport, settings: settings, notices: port)
        // What macOS says now, rather than the stored mirror — the same read the
        // settings page does on arrival. Without it `.system` falls back to the
        // menu-bar label and every banner assertion below is about the fallback.
        await model.refreshBannerAuthorization()

        let firing = VPNAutomation(at: Date(), name: "Office", kind: kind)
        let payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "A1", name: "Office",
                                        status: kind == .connected ? .connected : .disconnected,
                                        kind: "IKEv2")],
            autoConnected: [], defaultName: "Office", lastAutomation: firing)
        transport.emit(EngineEvent(name: "state",
                                   payload: try! JSONEncoder().encode(payload)))
        for _ in 0..<500 where model.lastAutomation == nil { await Task.yield() }
        await model.announcement?.value
        // The descriptor is asked rather than the model, because the menu-bar
        // name is its decision and it reads a different accessor.
        _ = descriptor.viewModel(host)
        return (port.posted, model.effectiveNotice(for: kind).showsMenuBarName
                ? model.lastAutomation?.name : nil)
    }

    /// The case the split exists for: the rules were told to be quiet and the
    /// tunnel fell over anyway.
    func testASelfDropSpeaksEvenWhenTheRulesWereSilenced() async {
        let said = await announce(kind: .dropped, rules: .silent, drop: .system)

        XCTAssertEqual(said.banner.count, 1,
                       "the tunnel fell over and the module read the rules' silence")
        // `first`, never a subscript: when the assertion above fails this test
        // has to *report* it, and an index into an empty array ends the whole
        // xctest process — which is how a mutation run comes back as a crash
        // with nothing said about the guard.
        XCTAssertEqual(said.banner.first?.1.contains("Office"), true,
                       "the banner did not name the connection: \(said.banner)")
    }

    /// The control, and it is not optional: without it every assertion above
    /// passes on a module that simply announces everything.
    func testARuleFiringStillObeysTheRulesSetting() async {
        let said = await announce(kind: .connected, rules: .silent, drop: .system)

        XCTAssertTrue(said.banner.isEmpty,
                      "a rule fired under chosen silence and posted a banner: \(said.banner)")
        XCTAssertNil(said.label, "…and named itself in the menu bar")
    }

    /// The other direction. Somebody who wants their rules announced loudly and
    /// does not want to be interrupted by a flaky network gets that too.
    func testASilencedDropStaysSilentWhileTheRulesSpeak() async {
        let quiet = await announce(kind: .dropped, rules: .system, drop: .silent)
        XCTAssertTrue(quiet.banner.isEmpty, "chosen silence was broken: \(quiet.banner)")
        XCTAssertNil(quiet.label)

        let loud = await announce(kind: .connected, rules: .system, drop: .silent)
        XCTAssertEqual(loud.banner.count, 1,
                       "precondition: the rules really are set to speak, so the silence above "
                       + "is the drop's setting rather than a model that announces nothing")
    }

    /// The teardown a quit rule performs is announced no more quietly than the
    /// fall it looks like from the outside — through the real path, because the
    /// view model chooses the mode and a test of `VPNSettings` alone would pass
    /// with this end still reading the rules' setting.
    ///
    /// The reason it is a security fix and not a preference: a quit can be
    /// provoked by anything running as this user, and a teardown is booked as a
    /// rule doing as it was told.
    func testAProvokedTeardownIsNotQuieterThanTheFallItLooksLike() async {
        let said = await announce(kind: .disconnected, rules: .silent, drop: .system)

        XCTAssertEqual(said.banner.count, 1,
                       "Helm took the tunnel down by itself and said so on the quiet channel, "
                       + "while the person had asked to hear about losing a tunnel")
    }

    /// And the control from the other side: with both settings quiet, nothing is
    /// said — the rule is «no quieter than a drop», not «always loud».
    func testATeardownIsStillSilentWhenBothChoicesAre() async {
        let said = await announce(kind: .disconnected, rules: .silent, drop: .silent)
        XCTAssertTrue(said.banner.isEmpty, "chosen silence was broken: \(said.banner)")
        XCTAssertNil(said.label)
    }

    /// A drop and a quit rule are different words, not only different volumes.
    /// «Not connected» is the state either way; what differs is that nobody
    /// asked for this one.
    func testADropAndAQuitRuleDoNotSayTheSameThing() async {
        let dropped = await announce(kind: .dropped, rules: .system, drop: .system)
        let byRule = await announce(kind: .disconnected, rules: .system, drop: .system)

        XCTAssertEqual(dropped.banner.count, 1)
        XCTAssertEqual(byRule.banner.count, 1)
        XCTAssertNotEqual(dropped.banner.first?.0, byRule.banner.first?.0,
                          "a tunnel that fell over and a rule taking one down were announced "
                          + "in the same words")
    }
}
