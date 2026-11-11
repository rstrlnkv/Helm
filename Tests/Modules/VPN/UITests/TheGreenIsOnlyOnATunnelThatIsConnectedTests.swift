// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **A green mark on a tunnel three seconds into a handshake says the Mac is
/// protected while it is not.** The settings page's dot and the button's colour,
/// the panel tile's header and its rows, and the 1×1 widget's figure and dot each
/// ask "is it up" by their own word, and `.connecting` is up in one vocabulary
/// (`isUp`) and not in the other (`isConnected`). Each surface now answers
/// through one hook (`VPNConnectionCard.lit`, `VPNPanelTile.lit`,
/// `VPNPanelTile.anyConnected`, `VPNCompactWidget.up`); this asks all four, for
/// every status, and wants green exactly on `.connected`.
///
/// What it cannot see: a body that stops calling its hook. That is a change of
/// look, and a look is proved by shots, not by this class.
@MainActor
final class TheGreenIsOnlyOnATunnelThatIsConnectedTests: XCTestCase {

    private static let everyStatus: [VPNStatus] = [.connected, .connecting, .disconnected,
                                                   .disconnecting, .unknown]

    /// A view model holding one connection in the given state, fed the way the app
    /// feeds it: an engine payload on its stream.
    private func model(_ status: VPNStatus) -> VPNViewModel {
        let work = FakeVPNWork()
        // In memory, never `UserDefaults.standard`.
        let settings = VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                         backing: InMemoryKeyValueStore()))
        let vm = VPNViewModel(work: work, settings: settings)
        work.say(VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: "One", status: status, kind: "IKEv2")],
            autoConnected: [], lastAutomation: nil))
        for _ in 0..<80 where vm.connections.isEmpty {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(vm.connections.count, 1,
                       "the stream did not deliver: the reading below would be of an empty list")
        return vm
    }

    func testEverySurfaceIsGreenExactlyWhenTheStatusIsConnected() {
        // The five statuses are listed by hand: `VPNStatus` is not `CaseIterable`,
        // so a case added to the enum must be added here too; this line only
        // catches a duplicate in the list.
        XCTAssertEqual(Set(Self.everyStatus.map(\.rawValue)).count, 5)
        for status in Self.everyStatus {
            let vm = model(status)
            let c = vm.connections[0]
            let want = status == .connected
            XCTAssertEqual(VPNConnectionCard.lit(c), want, "the card, \(status)")
            XCTAssertEqual(VPNPanelTile.lit(c), want, "a tile row, \(status)")
            XCTAssertEqual(VPNPanelTile(vm: vm).anyConnected, want, "the tile's header, \(status)")
            XCTAssertEqual(VPNCompactWidget(vm: vm).up, want ? 1 : 0, "the 1×1 widget, \(status)")
        }
    }
}
