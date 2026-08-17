// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The page draws six cards, and the connected tunnel is one of them.
///
/// `VPNGridLayout` and `VPNConnectionOrder` are each tested on their own; what
/// this holds is that the page applies them, and in the one order they can be
/// applied in. Capping before sorting is the same page with the defect back:
/// nine configurations, the ninth up, six drawn — and the card the page exists
/// for behind a button.
@MainActor
final class TheGridShowsWhatMattersFirstTests: XCTestCase {

    private func page(_ connections: [VPNConnection]) -> VPNSettingsPage {
        let transport = LocalTransport()
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        let vm = VPNViewModel(transport: transport, settings: settings)
        let payload = VPNEngine.StatePayload(connections: connections, autoConnected: [],
                                             defaultName: nil, lastAutomation: nil)
        transport.emit(EngineEvent(name: "state", payload: try! JSONEncoder().encode(payload)))
        for _ in 0..<50 where vm.connections.count != connections.count {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return VPNSettingsPage(vm: vm, store: store)
    }

    private func conn(_ name: String, _ status: VPNStatus) -> VPNConnection {
        VPNConnection(id: name, name: name, status: status, kind: "IKEv2")
    }

    func testTheNinthConnectionIsOnScreenWhenItIsTheOneThatIsUp() {
        let list = (1...9).map { conn("VPN \($0)", $0 == 9 ? .connected : .disconnected) }
        let shown = page(list).shownConnections
        XCTAssertEqual(shown.count, VPNGridLayout.collapsedLimit)
        XCTAssertEqual(shown.first?.name, "VPN 9")
    }

    func testNothingIsHiddenWhenThereIsNothingToHide() {
        let list = (1...VPNGridLayout.collapsedLimit).map { conn("VPN \($0)", .disconnected) }
        XCTAssertEqual(page(list).shownConnections.count, list.count)
    }

    /// The page holds no opinion of its own about the count — it asks the same
    /// question the grid does, so the cards drawn and the columns they are
    /// drawn in cannot disagree.
    func testTheCardsDrawnFillTheColumnsTheyAreDrawnIn() {
        for n in 1...12 {
            let list = (1...n).map { conn("VPN \($0)", .disconnected) }
            let shown = page(list).shownConnections.count
            let columns = VPNGridLayout.columns(for: n)
            XCTAssertLessThanOrEqual(VPNGridLayout.hole(count: shown, columns: columns), 1,
                                     "\(n) connections draw \(shown) cards in \(columns) columns")
        }
    }
}
