// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import SwiftUI
import AppKit
import HelmContract
import HelmRuntime
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The connection cards and the section cards under them are one column, in
/// pixels.
///
/// The connections block rides on a grouped `Form`'s **section header**, which
/// is the one part of such a form drawn on the bare pane and still scrolling.
/// A header is inset further than the section's own card — measured at the
/// settings column, 30 against 20 — and that is right for text: a heading sits
/// level with what the rows below *say*. It is wrong for a card. Photographed
/// before this test existed: the two connection cards ran 80…532 while the card
/// under them ran 70…774, so a page of cards had two left edges 10 pt apart and
/// a right edge nobody could line up.
///
/// `HelmLayout.groupedHeaderOutset` takes it back out, and the number belongs to
/// SwiftUI rather than to us — so this photographs both edges rather than
/// asserting the constant against itself, which would be a test whose two sides
/// read one value.
@MainActor
final class TheConnectionsLineUpWithTheCardsTests: XCTestCase {

    /// Two connections, so the grid fills the row: with one the card stops at
    /// half the row by design, and the right-hand edge this test reads would be
    /// measuring that rule instead of the alignment.
    private func page() -> (VPNSettingsPage, VPNViewModel) {
        let transport = LocalTransport()
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        // One rule, so the section below the header has a row in it and its
        // card is drawn at its natural width.
        settings.setRulesJSON(VPNRules.encode(["com.apple.Safari": VPNAppRule(vpnName: "One")]))
        let vm = VPNViewModel(transport: transport, settings: settings)
        let payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: "One", status: .disconnected, kind: "IKEv2"),
                          VPNConnection(id: "2", name: "Two", status: .connected, kind: "IKEv2")],
            autoConnected: [], defaultName: nil, lastAutomation: nil)
        transport.emit(EngineEvent(name: "state", payload: try! JSONEncoder().encode(payload)))
        for _ in 0..<50 where vm.connections.isEmpty {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return (VPNSettingsPage(vm: vm, store: store), vm)
    }

    private static let width: CGFloat = 845
    private static let height: CGFloat = 1000

    /// The left and right edge of whatever is drawn across one row of pixels,
    /// in points, measured against the pane behind it. Returns nil when nothing
    /// differs from the background there.
    private func edges(_ rep: NSBitmapImageRep, atPoint y: Int) -> (left: Int, right: Int)? {
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return nil }
        let row = rep.bytesPerRow
        // The pane itself, read where nothing is drawn: the top strip above the
        // first heading.
        let bg = (0..<3).map { Int(data[6 * row + (rep.pixelsWide / 2) * 4 + $0]) }
        var lo = -1, hi = -1
        // Inset from the window's own edges, which are a different colour from
        // the pane and would be found first.
        for x in 130..<(rep.pixelsWide - 120) {
            let p = y * 2 * row + x * 4
            let d = abs(Int(data[p]) - bg[0]) + abs(Int(data[p + 1]) - bg[1])
                + abs(Int(data[p + 2]) - bg[2])
            if d > 3 {
                if lo < 0 { lo = x }
                hi = x
            }
        }
        return lo < 0 ? nil : (lo / 2, hi / 2)
    }

    private func shoot() throws -> NSBitmapImageRep {
        let (view, _) = page()
        let host = NSHostingView(rootView: view.frame(width: Self.width, height: Self.height))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        window.layoutIfNeeded()
        for _ in 0..<40 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        window.contentView = nil
        return rep
    }

    /// The card row, at a height inside the connection cards, and the row of
    /// the per-app card below them.
    ///
    /// Both y values are read off the same photograph rather than assumed: the
    /// test asserts first that it found two different things, so a layout change
    /// that moved either block out from under its sample would fail here rather
    /// than compare a card with itself.
    func testTheConnectionCardsAndTheSectionCardShareOneColumn() throws {
        let rep = try shoot()
        try XCTSkipIf(rep.bitmapData == nil, "nothing drew — no window server")

        let cards = try XCTUnwrap(edges(rep, atPoint: 60),
                                  "nothing was drawn where the connection cards should be")
        let section = try XCTUnwrap(edges(rep, atPoint: 260),
                                    "nothing was drawn where the per-app card should be")

        XCTAssertGreaterThan(cards.right - cards.left, 400,
                             "the sample at y=60 did not land across both cards: \(cards)")
        XCTAssertEqual(cards.left, section.left,
                       "the connection cards start at \(cards.left) and the card below them at "
                       + "\(section.left) — two card systems on one page, 10 pt apart")
        XCTAssertEqual(cards.right, section.right,
                       "the connection cards end at \(cards.right) and the card below them at "
                       + "\(section.right)")
    }
}
