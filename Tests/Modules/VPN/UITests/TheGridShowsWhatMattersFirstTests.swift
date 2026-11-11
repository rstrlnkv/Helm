// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The page draws six cards, and the connected tunnel is one of them.
///
/// `VPNConnectionOrder` is tested on its own; what this holds is that the page
/// applies it and the cap, in the one order they can be applied in. Capping before sorting is the same page with the defect back:
/// nine configurations, the ninth up, six drawn — and the card the page exists
/// for behind a button.
@MainActor
final class TheGridShowsWhatMattersFirstTests: XCTestCase {

    private func page(_ connections: [VPNConnection]) -> VPNSettingsPage {
        let work = FakeVPNWork()
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        let vm = VPNViewModel(work: work, settings: settings)
        let payload = VPNEngine.StatePayload(connections: connections, autoConnected: [],
                                             lastAutomation: nil)
        work.say(payload)
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
}
