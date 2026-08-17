// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **A setting that is written and never read is a control that does nothing.**
///
/// The per-connection notices, the ring and its two colours are stored in
/// `VPNNoticeBook`, keyed by the configuration's id. The firing path — the
/// banner, the menu-bar name, the ring and its colour — read the module-wide
/// values instead, for the first hour those popovers existed: a person could set
/// one tunnel to silence and hear it announce itself for ever, with the store
/// holding exactly what they had asked for. Nothing failed, because every test
/// there was asked the book directly.
///
/// So these tests go through the model the way the menu bar does, and the join
/// they exercise is the one that had been missing: a firing carries the
/// configuration's *name* (`scutil --nc start` takes a name), the settings are
/// keyed by its *id*, and something has to turn one into the other.
@MainActor
final class TheRingTurnsInThisTunnelsColourTests: XCTestCase {

    private func model(_ connections: [(String, String)],
                       book: (VPNSettings) -> Void = { _ in }) -> VPNViewModel {
        let transport = LocalTransport()
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        settings.setNotice(.menuBar)
        settings.setDropNotice(.menuBar)
        settings.setAutomationSpin(true)
        book(settings)
        let vm = VPNViewModel(transport: transport, settings: settings)
        let payload = VPNEngine.StatePayload(
            connections: connections.map {
                VPNConnection(id: $0.0, name: $0.1, status: .disconnected, kind: "IKEv2")
            },
            autoConnected: [], defaultName: nil, lastAutomation: nil)
        transport.emit(EngineEvent(name: VPNEvent.state.rawValue,
                                   payload: try! JSONEncoder().encode(payload)))
        for _ in 0..<80 where vm.connections.isEmpty {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(vm.connections.count, connections.count,
                       "the wire did not deliver: nothing below measures anything")
        return vm
    }

    // MARK: - The join

    func testTheFiringsNameFindsTheConfigurationItHappenedOn() {
        let vm = model([("id-A", "Office"), ("id-B", "Home")])
        XCTAssertEqual(vm.connectionID(named: "Office"), "id-A")
        XCTAssertEqual(vm.connectionID(named: "Home"), "id-B")
        XCTAssertNil(vm.connectionID(named: "Nowhere"),
                     "a name this Mac does not have resolves to no configuration")
    }

    /// **Two configurations may carry one display name**, which is the fact
    /// `_cameUp` was re-keyed for. A per-connection setting applied to a firing
    /// that might be the namesake's is a setting applied to the wrong tunnel, so
    /// the join refuses and the module-wide value answers.
    func testTwoConfigurationsOfOneNameResolveToNeither() {
        let vm = model([("id-A", "Office"), ("id-B", "Office")],
                       book: { settings in
            settings.setNoticeBook(VPNNoticeBook().setting("id-A", notice: .silent))
        })
        XCTAssertNil(vm.connectionID(named: "Office"))
        XCTAssertEqual(vm.notice(for: .connected, on: "Office"), .menuBar,
                       "one namesake's silence was applied to a firing that may be the other's")
    }

    // MARK: - What a firing reads

    func testASilencedTunnelIsSilentAndItsNeighbourIsNot() {
        let vm = model([("id-A", "Office"), ("id-B", "Home")], book: { settings in
            settings.setNoticeBook(VPNNoticeBook().setting("id-A", notice: .silent))
        })
        XCTAssertEqual(vm.notice(for: .connected, on: "Office"), .silent)
        XCTAssertEqual(vm.notice(for: .connected, on: "Home"), .menuBar,
                       "the neighbour inherits, and inherits the app's own setting")
    }

    func testTheRingObeysTheCardsSwitch() {
        let vm = model([("id-A", "Office"), ("id-B", "Home")], book: { settings in
            settings.setNoticeBook(VPNNoticeBook().setting("id-A", spin: false))
        })
        XCTAssertFalse(vm.automationSpin(on: "Office"),
                       "the card asked for no movement and got the module's answer")
        XCTAssertTrue(vm.automationSpin(on: "Home"))
    }

    /// The colours, per configuration and per direction. Two fields for three
    /// kinds: a teardown Helm performed and a tunnel that fell over are both
    /// «down», which is the same arithmetic the store's two keys do.
    func testEachTunnelTurnsTheRingInItsOwnColour() {
        let vm = model([("id-A", "Office"), ("id-B", "Home")], book: { settings in
            settings.setNoticeBook(VPNNoticeBook()
                .setting("id-A", tint: "purple", for: .connected)
                .setting("id-A", tint: "red", for: .dropped))
        })
        XCTAssertEqual(vm.spinTint(for: .connected, on: "Office"), "purple")
        XCTAssertEqual(vm.spinTint(for: .dropped, on: "Office"), "red")
        XCTAssertEqual(vm.spinTint(for: .disconnected, on: "Office"), "red",
                       "a teardown Helm performed is the same direction as a fall")
        XCTAssertEqual(vm.spinTint(for: .connected, on: "Home"), "green",
                       "the neighbour keeps the colour the app shipped with")
        XCTAssertEqual(vm.spinTint(for: .disconnected, on: "Home"), "orange")
    }

    /// A configuration that has said nothing about colour still follows the
    /// module-wide colour, so the fallback is the store's value and not a
    /// constant spelled twice.
    func testAnUntouchedTunnelFollowsTheModuleWideColour() {
        let vm = model([("id-A", "Office")], book: { settings in
            settings.setSpinTint("blue", for: .connected)
        })
        XCTAssertEqual(vm.spinTint(for: .connected, on: "Office"), "blue")
    }

    // MARK: - The firing path asks on the configuration, not the module

    /// The half a model-level test cannot reach: **that the menu bar's own path
    /// calls these methods at all.** `statusAppearance` builds what the host
    /// draws from three questions, and for the first hour these settings existed
    /// it asked all three module-wide — so every reading above would have been
    /// green while the popover changed nothing. Driving the descriptor here is
    /// not the answer: its view model comes with the app's real store as a
    /// default argument, and eleven engine tests once rolled back the owner's
    /// own Autopilot exactly that way (CLAUDE.md). So the guard is on the
    /// source: in the firing path, each of the three is asked with the
    /// configuration's name.
    func testTheDescriptorAsksAllThreeOnTheConfigurationThatFired() throws {
        let file = RepoSource.root
            .appendingPathComponent("Sources/Modules/VPN/UI/VPNDescriptor.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        for call in ["model.automationSpin(on: firing.name)",
                     "model.effectiveNotice(for: firing.kind, on: firing.name)",
                     "model.spinTint(for: firing.kind, on: firing.name)"] {
            XCTAssertTrue(source.contains(call),
                          "the firing path does not ask «\(call)» — a card's setting is written "
                          + "to the store and never read")
        }
        for moduleWide in ["model.automationSpin\n", "model.automationSpin ",
                           "model.effectiveNotice(for: firing.kind)",
                           "model.spinTint(for: firing.kind)"] {
            XCTAssertFalse(source.contains(moduleWide),
                           "the firing path still reads «\(moduleWide)» module-wide")
        }
    }

    /// And the banner's own mode, which is decided in the model rather than in
    /// the descriptor.
    func testTheBannerIsAnnouncedInThisConfigurationsVoice() throws {
        let file = RepoSource.root
            .appendingPathComponent("Sources/Modules/VPN/UI/VPNViewModel.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(source.contains("let mode = notice(for: firing.kind, on: firing.name)"),
                      "the banner is announced in the module's voice, not the configuration's")
    }
}
