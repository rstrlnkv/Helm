// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import Foundation
import HelmRuntime
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **A setting that is written and never read is a control that does nothing.**
///
/// The per-connection notices, the ring and its two colours are stored in
/// `VPNNoticeBook`, keyed by the configuration's id. If the firing path — the
/// banner, the menu-bar name, the ring and its colour — read the module-wide
/// values instead, a person could set one tunnel to silence and hear it
/// announce itself, with the store holding exactly what they asked for, and a
/// test that asks the book directly would not notice.
///
/// So these tests go through the model the way the menu bar does: a firing
/// carries the configuration's *name* (`scutil --nc start` takes a name), the
/// settings are keyed by its *id*, and the join turns one into the other.
///
/// Guards: a firing's name is joined to the configuration id its per-tunnel settings are keyed by.
@MainActor
final class TheRingTurnsInThisTunnelsColourTests: XCTestCase {

    private func model(_ connections: [(String, String)],
                       book: (VPNSettings) -> Void = { _ in }) async -> VPNViewModel {
        let work = FakeVPNWork()
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        settings.store.set(VPNNotice.menuBar.rawValue, for: VPNSettings.automationNoticeKey)
        settings.store.set(VPNNotice.menuBar.rawValue, for: VPNSettings.dropNoticeKey)
        settings.store.set(true, for: VPNSettings.automationSpinKey)
        book(settings)
        let vm = VPNViewModel(work: work, settings: settings)
        let payload = VPNEngine.StatePayload(
            connections: connections.map {
                VPNConnection(id: $0.0, name: $0.1, status: .disconnected, kind: "IKEv2")
            },
            autoConnected: [], lastAutomation: nil)
        work.say(payload)
        await waitUntil("the payload handled") { !vm.connections.isEmpty }
        XCTAssertEqual(vm.connections.count, connections.count,
                       "the stream did not deliver: nothing below measures anything")
        return vm
    }

    // MARK: - The join

    func testTheFiringsNameFindsTheConfigurationItHappenedOn() async {
        let vm = await model([("id-A", "Office"), ("id-B", "Home")])
        XCTAssertEqual(vm.connectionID(named: "Office"), "id-A")
        XCTAssertEqual(vm.connectionID(named: "Home"), "id-B")
        XCTAssertNil(vm.connectionID(named: "Nowhere"),
                     "a name this Mac does not have resolves to no configuration")
    }

    /// **Two configurations may carry one display name.** A per-connection
    /// setting applied to a firing that might be the namesake's is applied to the
    /// wrong tunnel, so the join refuses and the module-wide value answers.
    func testTwoConfigurationsOfOneNameResolveToNeither() async {
        let vm = await model([("id-A", "Office"), ("id-B", "Office")],
                       book: { settings in
            settings.setNoticeBook(VPNNoticeBook().setting("id-A", notice: .silent))
        })
        XCTAssertNil(vm.connectionID(named: "Office"))
        XCTAssertEqual(vm.notice(for: .connected, on: "Office"), .menuBar,
                       "one namesake's silence was applied to a firing that may be the other's")
    }

    // MARK: - What a firing reads

    func testASilencedTunnelIsSilentAndItsNeighbourIsNot() async {
        let vm = await model([("id-A", "Office"), ("id-B", "Home")], book: { settings in
            settings.setNoticeBook(VPNNoticeBook().setting("id-A", notice: .silent))
        })
        XCTAssertEqual(vm.notice(for: .connected, on: "Office"), .silent)
        XCTAssertEqual(vm.notice(for: .connected, on: "Home"), .menuBar,
                       "the neighbour inherits, and inherits the app's own setting")
    }

    func testTheRingObeysTheCardsSwitch() async {
        let vm = await model([("id-A", "Office"), ("id-B", "Home")], book: { settings in
            settings.setNoticeBook(VPNNoticeBook().setting("id-A", spin: false))
        })
        XCTAssertFalse(vm.automationSpin(on: "Office"),
                       "the card asked for no movement and got the module's answer")
        XCTAssertTrue(vm.automationSpin(on: "Home"))
    }

    /// The colours, per configuration and per direction. Two fields for three
    /// kinds: a teardown Helm performed and a tunnel that fell over are both
    /// «down», which is the same arithmetic the store's two keys do.
    func testEachTunnelTurnsTheRingInItsOwnColour() async {
        let vm = await model([("id-A", "Office"), ("id-B", "Home")], book: { settings in
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
    func testAnUntouchedTunnelFollowsTheModuleWideColour() async {
        let vm = await model([("id-A", "Office")], book: { settings in
            settings.store.set("blue", for: VPNSettings.spinTintKey(.connected))
        })
        XCTAssertEqual(vm.spinTint(for: .connected, on: "Office"), "blue")
    }

    /// A name this Mac does not have answers with the module-wide values.
    func testAFiringOnAnUnknownNameFollowsTheModuleWideValues() async {
        let vm = await model([("id-A", "Office")], book: { settings in
            settings.store.set("blue", for: VPNSettings.spinTintKey(.connected))
            settings.store.set(false, for: VPNSettings.automationSpinKey)
        })
        XCTAssertEqual(vm.spinTint(for: .connected, on: "Nowhere"), "blue")
        XCTAssertFalse(vm.automationSpin(on: "Nowhere"))
    }

    // MARK: - The firing path asks on the configuration, not the module
}
