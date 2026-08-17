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

/// Since the ring came off, the button's colour is the page's answer to «which
/// one is up» — so it is measured, in the button's own corner of the card.
///
/// The connected card used to be outlined in `HelmSignal.success`. A row of
/// cards with one outlined reads as a selection, which is what the accent ring
/// on the notice previews further down this page actually is, so the green
/// moved to the mark the row is about. That makes it the kind of claim that can
/// stop being true without anybody noticing: a tint edited to the accent, a
/// state read as `isUp` instead of `isConnected`, and the page goes on looking
/// finished.
///
/// Counted in the trailing 40 pt of the card and nowhere else — the dot at the
/// leading edge is the *other* green mark, and counting the whole card would
/// pass on the dot alone with the button's colour gone.
@MainActor
final class TheGreenIsOnTheOneThatIsUpTests: XCTestCase {

    private func shoot(_ status: VPNStatus) throws -> NSBitmapImageRep {
        let width: CGFloat = 845, height: CGFloat = 400
        let transport = LocalTransport()
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        let vm = VPNViewModel(transport: transport, settings: settings)
        let payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: "One", status: status, kind: "IKEv2")],
            autoConnected: [], defaultName: nil, lastAutomation: nil)
        transport.emit(EngineEvent(name: "state", payload: try! JSONEncoder().encode(payload)))
        for _ in 0..<50 where vm.connections.isEmpty {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let host = NSHostingView(rootView: VPNSettingsPage(vm: vm, store: store)
            .frame(width: width, height: height).helmMeasuringBench())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.layoutIfNeeded()
        for _ in 0..<60 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        window.contentView = nil
        return rep
    }

    /// Pixels close to the signal colour, in the card's trailing corner: one
    /// connection draws a card half the row wide, so the button sits around
    /// x = 380…410 pt and the dot is 300 pt away from there.
    private func greenInTheButtonsCorner(_ rep: NSBitmapImageRep) throws -> Int {
        let data = try XCTUnwrap(rep.bitmapData)
        let row = rep.bytesPerRow
        // **Green-dominant rather than a colour match.** The bench draws in
        // whichever appearance this Mac is in, and `HelmSignal.success` is two
        // different colours in the two — a match against one of them would be a
        // test that passes for the wrong reason half the year. Both are far
        // greener than they are red or blue; the accent is blue-dominant and
        // `HelmText.quiet` is neither.
        var count = 0
        for y in 30..<110 {
            for x in 330..<430 {
                let p = y * 2 * row + x * 2 * 4
                let r = Int(data[p]), g = Int(data[p + 1]), b = Int(data[p + 2])
                if g - r > 40, g - b > 40 { count += 1 }
            }
        }
        return count
    }

    func testTheButtonIsGreenOnlyOnceTheTunnelIsUp() throws {
        let up = try greenInTheButtonsCorner(try shoot(.connected))
        // The precondition first: an assertion that a colour is absent passes
        // on a page that drew nothing at all.
        XCTAssertGreaterThan(up, 20,
                             "precondition: the connected card draws the signal colour on its "
                             + "button at all (\(up) px) — nothing below can fail otherwise")
        XCTAssertEqual(try greenInTheButtonsCorner(try shoot(.connecting)), 0,
                       "a handshake in flight wears the colour that means the Mac is behind a "
                       + "tunnel")
        XCTAssertEqual(try greenInTheButtonsCorner(try shoot(.disconnected)), 0,
                       "a tunnel that is down wears the colour that means it is up")
    }

    /// A mark that carries meaning answers to 3:1, and this one now carries the
    /// meaning the ring used to: the ring measured 3.40:1 on the card fill.
    func testTheGreenMarkClearsTheMarkFloorOnTheButtonsDisc() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = Contrast.system(\.windowBackgroundColor, appearance)
            let card = Contrast.over(Contrast.resolved(HelmSurface.wellFill, appearance), window)
            let disc = Contrast.over(Contrast.resolved(HelmSurface.onPanelFill, appearance), card)
            let ink = Contrast.resolved(HelmSignal.success, appearance)
            let ratio = Contrast.ratio(ink, disc)
            XCTAssertGreaterThanOrEqual(ratio, Contrast.markFloor,
                                        "the green mark measures \(ratio):1 on its own disc in "
                                        + "\(appearance.rawValue)")
        }
    }
}
