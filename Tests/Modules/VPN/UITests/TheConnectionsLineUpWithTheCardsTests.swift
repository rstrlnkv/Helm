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

/// The connection cards and the section card under them are one column, in
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
///
/// **The card underneath is the page's news now.** The rules and the notices were
/// two more sections and 800 pt of page; they are popovers on the card that owns
/// them, and the one section left is what the page has to say — so the fixture
/// gives it something to say. Which card it is does not matter to the reading —
/// where it is does, so its row comes from its own AppKit frame rather than from
/// a number typed here.
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
        var payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: "One", status: .disconnected, kind: "IKEv2"),
                          VPNConnection(id: "2", name: "Two", status: .connected, kind: "IKEv2")],
            autoConnected: [], defaultName: nil, lastAutomation: nil)
        // Something for the page's one section to hold, so there is a card under
        // the connections to line them up with.
        payload.secretsBehindAPrompt = ["One"]
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

    /// **The row the connection cards are on, found rather than typed.**
    ///
    /// It was `60`, which was inside the cards for exactly as long as the
    /// connections were the first thing on the page. They are not: the hero
    /// stands above them now, so that number moved into a sentence and the
    /// probe reported «nothing was drawn where the connection cards should be»
    /// — the failure this test's own doc comment predicts for a typed row, one
    /// paragraph after typing one.
    ///
    /// A card is told from a line of text by **density**, not by width: the
    /// closing notes run the full column at 13 pt and a headline runs most of
    /// it at 26, and both are ink with paper between the letters. A card is a
    /// fill, so nearly every pixel between its edges differs from the pane —
    /// the two cards side by side leave one 12 pt gap in about 450 pt, which is
    /// still over 90 %.
    private func cardsRow(_ rep: NSBitmapImageRep) -> Int? {
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return nil }
        let row = rep.bytesPerRow
        let bg = (0..<3).map { Int(data[6 * row + (rep.pixelsWide / 2) * 4 + $0]) }
        for y in 0..<(rep.pixelsHigh / 2) {
            guard let span = edges(rep, atPoint: y), span.right - span.left > 400 else { continue }
            var ink = 0
            for x in (span.left * 2)...(span.right * 2) {
                let p = y * 2 * row + x * 4
                let d = abs(Int(data[p]) - bg[0]) + abs(Int(data[p + 1]) - bg[1])
                    + abs(Int(data[p + 2]) - bg[2])
                if d > 3 { ink += 1 }
            }
            guard Double(ink) / Double((span.right - span.left) * 2) > 0.9 else { continue }
            // **Not this row — the widest one just below it.** The first filled
            // row of a rounded card is inside its own corner, so it is narrower
            // than the card by the radius at each end: measured here, 78…766
            // against the card's true 70…774, which is `HelmRadius.card` twice
            // over and would have been read as the cards missing their column
            // by 8 pt. The corner is done within 30 pt of the top on any radius
            // this house draws.
            return (y..<min(rep.pixelsHigh / 2, y + 30))
                .max { (edges(rep, atPoint: $0).map { $0.right - $0.left } ?? 0)
                     < (edges(rep, atPoint: $1).map { $0.right - $0.left } ?? 0) }
        }
        return nil
    }

    private func shoot() throws -> (rep: NSBitmapImageRep, host: NSView) {
        let (view, _) = page()
        // This window never orders in, and a page that idles off screen
        // (`helmIdlesOffScreen`) would hand the bitmap an empty pane.
        let host = NSHostingView(rootView: view.frame(width: Self.width, height: Self.height)
            .helmMeasuringBench())
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
        return (rep, host)
    }

    /// The row to sample the section card on: the middle of the first one the form
    /// draws, in the host's own points. A number typed here would be measuring
    /// whatever the page happens to put at that height — which is how the first
    /// version of this test survived the page losing two of its three sections.
    private func sectionCardRow(_ host: NSView) throws -> (row: Int, frame: NSRect) {
        let frames = Set(host.everyView(named: "_NSGraphicsView").map(\.frame))
            .sorted { $0.minY < $1.minY }
        let card = try XCTUnwrap(frames.first, "the form drew no section card at all")
        let inHost = host.convert(card, from: card.superview(in: host))
        return (Int(inHost.midY.rounded()), inHost)
    }

    /// The card row, at a height inside the connection cards, and the row of
    /// the section card below them.
    ///
    /// Both y values are read off the same photograph rather than assumed: the
    /// test asserts first that it found two different things, so a layout change
    /// that moved either block out from under its sample would fail here rather
    /// than compare a card with itself.
    func testTheConnectionCardsAndTheSectionCardShareOneColumn() throws {
        let (rep, host) = try shoot()
        try XCTSkipIf(rep.bitmapData == nil, "nothing drew — no window server")

        let cardsAt = try XCTUnwrap(cardsRow(rep),
                                    "no filled row the width of a card was drawn at all")
        let cards = try XCTUnwrap(edges(rep, atPoint: cardsAt),
                                  "nothing was drawn where the connection cards should be")
        let below = try sectionCardRow(host)
        let section = try XCTUnwrap(edges(rep, atPoint: below.row),
                                    "nothing was drawn across the section card at y=\(below.row)")
        // The pixels found the card AppKit named, and not something beside it.
        XCTAssertEqual(section.left, Int(below.frame.minX.rounded()), accuracy: 1,
                       "the fill photographed at y=\(below.row) starts at \(section.left) and the "
                       + "card AppKit reports at \(Int(below.frame.minX)) — two different things")

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
