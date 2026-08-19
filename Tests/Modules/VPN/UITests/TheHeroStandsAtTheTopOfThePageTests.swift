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

/// **The tunnel is the first thing on this page, and it was the last.**
///
/// What a person opens the VPN page to find out is whether their traffic is
/// really in the tunnel and where it comes out. Both were a 13 pt line at the
/// bottom of a card in the page's last section — under a grid that holds six
/// connections before it starts hiding them, which on an ordinary Mac is below
/// the fold. The block is the page's hero now, above the connections, in the
/// shape `KeepAwakeSettingsPage.sessionHero` already uses.
///
/// **Photographed rather than reasoned about.** «Above» is a fact about the
/// drawing and there is no value that carries it: a `Form`'s section header is
/// SwiftUI's to place, so a test that read the view tree would be asserting the
/// order of two things in a `VStack` — true in the source and no evidence at all
/// about the page. Every row here is found in the bitmap, never typed:
/// `TheConnectionsLineUpWithTheCardsTests` records what a typed row costs when
/// the page above it changes, which is exactly the change this test is about.
@MainActor
final class TheHeroStandsAtTheTopOfThePageTests: XCTestCase {

    private static let width: CGFloat = 845
    private static let height: CGFloat = 1000

    private func tunnel() -> VPNTunnelState {
        VPNTunnelState(name: "One", interface: "utun4",
                       since: Date(timeIntervalSince1970: 1_700_000_000),
                       bytesIn: 1_200_000_000, bytesOut: 210_000_000,
                       exit: .throughTunnel(countryCode: "NL"), speed: nil)
    }

    /// The page with two connections, and with or without a tunnel up.
    private func shoot(tunnels: [VPNTunnelState]) throws -> NSBitmapImageRep {
        let transport = LocalTransport()
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let vm = VPNViewModel(transport: transport, settings: VPNSettings(store: store))
        var payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: "One", status: .connected, kind: "IKEv2"),
                          VPNConnection(id: "2", name: "Two", status: .disconnected, kind: "IKEv2")],
            autoConnected: [], defaultName: nil, lastAutomation: nil)
        payload.tunnels = tunnels
        transport.emit(EngineEvent(name: "state", payload: try JSONEncoder().encode(payload)))
        for _ in 0..<50 where vm.connections.isEmpty {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let page = VPNSettingsPage(vm: vm, store: store)
        // This window never orders in, and a page that idles off screen
        // (`helmIdlesOffScreen`) would hand the bitmap an empty pane.
        let host = NSHostingView(rootView: page.frame(width: Self.width, height: Self.height)
            .helmMeasuringBench())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        window.layoutIfNeeded()
        for _ in 0..<60 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        window.contentView = nil
        return rep
    }

    // MARK: - Reading the photograph

    /// The pane's own colour, read where nothing is drawn.
    private func pane(_ rep: NSBitmapImageRep, _ data: UnsafePointer<UInt8>) -> [Int] {
        (0..<3).map { Int(data[6 * rep.bytesPerRow + (rep.pixelsWide / 2) * 4 + $0]) }
    }

    /// The leftmost and rightmost ink on one row of the drawing, in points.
    private func edges(_ rep: NSBitmapImageRep, atPoint y: Int) -> (left: Int, right: Int)? {
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return nil }
        let bg = pane(rep, data)
        var lo = -1, hi = -1
        // Inset from the window's own edges, which are a different colour from
        // the pane and would be found first.
        for x in 130..<(rep.pixelsWide - 120) {
            let p = y * 2 * rep.bytesPerRow + x * 4
            let d = abs(Int(data[p]) - bg[0]) + abs(Int(data[p + 1]) - bg[1])
                + abs(Int(data[p + 2]) - bg[2])
            if d > 3 {
                if lo < 0 { lo = x }
                hi = x
            }
        }
        return lo < 0 ? nil : (lo / 2, hi / 2)
    }

    /// The first row carrying any ink at all — the top of whatever the page
    /// draws first.
    private func firstInkRow(_ rep: NSBitmapImageRep) -> Int? {
        (0..<(rep.pixelsHigh / 2)).first { edges(rep, atPoint: $0) != nil }
    }

    /// The row the connection cards are on: a **fill** the width of a card,
    /// told from a line of text by density rather than by width — the closing
    /// notes run the full column and a headline runs most of it, and both are
    /// ink with paper between the letters.
    private func cardsRow(_ rep: NSBitmapImageRep) -> Int? {
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return nil }
        let bg = pane(rep, data)
        for y in 0..<(rep.pixelsHigh / 2) {
            guard let span = edges(rep, atPoint: y), span.right - span.left > 400 else { continue }
            var ink = 0
            for x in (span.left * 2)...(span.right * 2) {
                let p = y * 2 * rep.bytesPerRow + x * 4
                let d = abs(Int(data[p]) - bg[0]) + abs(Int(data[p + 1]) - bg[1])
                    + abs(Int(data[p + 2]) - bg[2])
                if d > 3 { ink += 1 }
            }
            if Double(ink) / Double((span.right - span.left) * 2) > 0.9 { return y }
        }
        return nil
    }

    // MARK: - The order on the page

    func testTheTunnelIsDrawnAboveTheConnections() throws {
        let rep = try shoot(tunnels: [tunnel()])
        try XCTSkipIf(rep.bitmapData == nil, "nothing drew — no window server")

        let hero = try XCTUnwrap(firstInkRow(rep), "the page drew nothing at all")
        let cards = try XCTUnwrap(cardsRow(rep),
                                  "no filled row the width of a card was drawn, so there is "
                                  + "nothing to be above")
        XCTAssertLessThan(hero, cards, """
            the first thing on the page is at y=\(hero) and the connection cards at \
            y=\(cards): the tunnel is under the grid again, which on a Mac with six \
            connections is under the fold
            """)
        // And it is a block rather than a stray pixel: the headline, the
        // segments and four columns do not fit in 40 pt.
        XCTAssertGreaterThan(cards - hero, 100, """
            only \(cards - hero) pt stand above the connection cards, which is less \
            than the hero takes — so what was found is not the hero
            """)
    }

    /// **The slot answers with nothing up, and it used to disappear.**
    ///
    /// Right for a section three quarters of the way down a page and wrong for
    /// the first block on it: a slot that vanishes takes the page's shape with
    /// it. The assertion is that the page still draws something above the
    /// cards, and it needs its own precondition — an absence would also hold if
    /// the whole page failed to draw.
    func testTheSlotStillAnswersWithNoTunnelUp() throws {
        let rep = try shoot(tunnels: [])
        try XCTSkipIf(rep.bitmapData == nil, "nothing drew — no window server")

        let hero = try XCTUnwrap(firstInkRow(rep), "the page drew nothing at all")
        let cards = try XCTUnwrap(cardsRow(rep), "the connections themselves did not draw")
        XCTAssertLessThan(hero, cards,
                          "the top of the page is empty with no tunnel up, so the page has "
                          + "one shape with a VPN connected and another without")
        // Two lines of copy, not the one-line heading that used to sit here.
        XCTAssertGreaterThan(cards - hero, 40, """
            \(cards - hero) pt above the cards is less than the empty state's two \
            lines, so the sentence that says what appears here is missing
            """)
    }
}
