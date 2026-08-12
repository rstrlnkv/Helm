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

/// **The green dot in the panel, three seconds into a handshake.**
///
/// The settings page draws its dot from `isConnected` and says why in its own
/// comment: «a green dot on a tunnel that is three seconds into coming up is the
/// page saying the Mac is protected when it is not». The panel tile — the surface
/// somebody actually glances at before typing something they would not send in
/// clear — asked `isUp`, which is `.connected || .connecting`. Two surfaces, one
/// question, two answers.
///
/// Read off the drawing rather than off the source, because the defect is a
/// colour: `HelmStatusDot` has no frame of its own to inspect, and which
/// vocabulary word a view calls is invisible at runtime except here.
@MainActor
final class ADotIsNotGreenBeforeATunnelIsUpTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    /// A view model holding one connection in the given state, fed the way the app
    /// feeds it: an engine payload over the transport.
    private func model(_ status: VPNStatus) -> VPNViewModel {
        let transport = LocalTransport()
        // In memory, never `UserDefaults.standard`.
        let settings = VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                         backing: InMemoryKeyValueStore()))
        let vm = VPNViewModel(transport: transport, settings: settings)
        let payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: "One", status: status, kind: "IKEv2")],
            autoConnected: [], defaultName: "One", lastAutomation: nil)
        transport.emit(EngineEvent(name: "state",
                                   payload: try! JSONEncoder().encode(payload)))
        for _ in 0..<80 where vm.connections.isEmpty {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(vm.connections.count, 1,
                       "the wire did not deliver: the reading below would be of an empty tile")
        return vm
    }

    /// How many pixels of a panel view are the design system's *success* colour —
    /// the one thing on either of them that means «up».
    ///
    /// Pinned to light appearance, like every other reading in this house: the
    /// dark green is `.systemGreen` and the light one is the token's own value,
    /// and `NSApp` in a test process is whatever this Mac is set to this hour.
    private func successPixels<V: View>(_ status: VPNStatus,
                                        _ build: (VPNViewModel) -> V) -> Int {
        let render = MountedRender(build(model(status)), width: 320, height: 220,
                                   appearance: .aqua)
        renders.append(render)
        render.settle(40)
        let view = render.host
        // `-1` rather than 0 or a skip when nothing was photographed: 0 would
        // satisfy every «no green here» assertion below by having no drawing at
        // all, which is the way a test of an absence stops being a test.
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return -1 }
        // Into the **bitmap's** colour space, not sRGB: `cacheDisplay` draws in
        // the display's, and this Mac's is wide — the token's own (32, 135, 58)
        // arrives as (66, 133, 67), which is 34 away on a channel and reads as
        // «no green anywhere» to a tolerance tight enough to mean anything.
        let want = Contrast.resolved(HelmSignal.success, .aqua)
            .usingColorSpace(rep.colorSpace) ?? Contrast.resolved(HelmSignal.success, .aqua)
        let target = [want.redComponent, want.greenComponent, want.blueComponent]
            .map { Int(($0 * 255).rounded()) }
        var found = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let at = y * rep.bytesPerRow + x * 4
                let far = (0..<3).map { abs(Int(data[at + $0]) - target[$0]) }.max() ?? 255
                if far <= 12 { found += 1 }
            }
        }
        return found
    }

    /// The three states together, so the claim is «the dot follows *connected*»
    /// rather than a pair of numbers — and the connected reading is the
    /// precondition: an assertion that a colour is absent passes on a tile that
    /// never drew anything at all.
    func testTheTilesDotIsGreenOnlyOnceTheTunnelIsUp() {
        assertTheGreenFollowsTheTunnel("the 2×1 tile") { VPNPanelTile(vm: $0) }
    }

    /// **The 1×1 widget had it too**, and it is the panel's smallest surface: its
    /// own dot and its «up of how many» figure both counted `.connecting`, which
    /// is the number `VPNStatus.isConnected`'s doc comment was written about.
    func testTheCompactWidgetsDotIsGreenOnlyOnceTheTunnelIsUp() {
        assertTheGreenFollowsTheTunnel("the 1×1 widget") { VPNCompactWidget(vm: $0) }
    }

    private func assertTheGreenFollowsTheTunnel<V: View>(_ what: String,
                                                         _ build: (VPNViewModel) -> V) {
        let up = successPixels(.connected, build)
        XCTAssertGreaterThan(up, 20,
                             "precondition: \(what) draws the success colour for a connected "
                             + "tunnel at all (\(up) px) — nothing below can fail otherwise")
        XCTAssertEqual(successPixels(.connecting, build), 0,
                       "\(what) says this Mac is behind a tunnel that has not come up")
        XCTAssertEqual(successPixels(.disconnected, build), 0, "the control for \(what)")
    }
}
