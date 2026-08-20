// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **A verdict that runs onto a second line is drawn about one axis**, and a
/// glyph beside the sentence was quietly moving the first of them.
///
/// The verdict wore a tick or a warning triangle inside the centred row, so the
/// *row* was centred and the sentence was not: photographed at the settings
/// window's 845 pt pane, the row centred on the pane at 422.5 while the sentence
/// alone centred at 438.75 and the caption under it at 422.5 — a headline
/// 16.25 pt right of its own caption, in a block whose whole shape is «one
/// centred column». Where the verdict wraps, the same fact is visible in one
/// drawing and is what this reads: the first line carries the mark and the
/// second does not, so the two are drawn about axes 18.25 pt apart.
///
/// **The caption is deliberately not compared with the figure, and the reason is
/// the reading rather than the layout.** Ink is not a line box: measured on the
/// empty hero with both lines centred and nothing wrong with either, Japanese
/// draws its 40 pt sentence with its ink 5 pt right of the box's own axis and
/// its caption 3 pt left of it, because a CJK glyph sits inside a full-width em
/// with real side bearings. 8.75 pt of honest disagreement leaves no room for a
/// threshold that would still mean something against 16.25. So what is compared
/// here is lines of **one string at one size**, where the bearings are the same
/// on every line — and the caption's own centring is carried by construction,
/// by `helmHeroSentence()`, which both slots take.
///
/// Swept over all eight languages and both widths, because whether the verdict
/// wraps at all is a fact about the language and the window rather than about
/// the layout — the argument `StringsCoverageTests` makes about a table.
@MainActor
final class AWrappedVerdictIsStillCentredTests: XCTestCase {

    /// **A floor read off the drawing, not a round number.** Two lines of one
    /// centred string do not agree to the pixel: the widest innocent
    /// disagreement measured over both states, both widths and all eight
    /// languages is 4.25 pt, in Japanese, where a glyph's ink sits off-centre
    /// inside its full-width em. The defect this exists for measures 18.25 to
    /// 23.75 in the same sweep.
    private static let apart: CGFloat = 8

    private var renders: [MountedRender] = []

    override func tearDown() async throws {
        renders.forEach { $0.drop() }
        renders = []
        AppLanguage.override = nil
        try await super.tearDown()
    }

    private func tunnel() -> VPNTunnelState {
        VPNTunnelState(name: "incy", interface: "utun4",
                       since: Date(timeIntervalSince1970: 1_700_000_000 - 4440),
                       bytesIn: 143_700_000, bytesOut: 19_800_000,
                       exit: .throughTunnel(countryCode: "NL"), speed: nil)
    }

    private func figure(_ tunnels: [VPNTunnelState], _ language: AppLanguage,
                        width: CGFloat) -> [RenderedLines.Line]? {
        AppLanguage.override = language
        let hero = VPNTunnelHero(tunnels, selected: .constant(nil),
                                 now: Date(timeIntervalSince1970: 1_700_000_000),
                                 measuring: nil, measure: { _ in })
        let render = MountedRender(hero, width: width, height: 400, appearance: .aqua)
        renders.append(render)
        render.settle()
        // The bitmap is taken inside the read, so the window has nothing left to
        // hold once it has been.
        defer { render.drop() }
        return HeroFigure.lines(of: render.host)
    }

    func testTheLiveVerdictIsCentredWhereverItWraps() throws {
        try sweep("a tunnel carrying the traffic") { [self.tunnel()] }
    }

    /// The state a Mac with no VPN shows every time.
    func testTheEmptySentenceIsCentredWhereverItWraps() throws {
        try sweep("no tunnel up") { [] }
    }

    private func sweep(_ state: String, _ tunnels: () -> [VPNTunnelState]) throws {
        var wrapped: [String] = []
        for width in HeroFigure.widths {
            for language in AppLanguage.allCases {
                let lines = try XCTUnwrap(figure(tunnels(), language, width: width),
                                          "nothing drew at \(Int(width)) pt — no window server")
                XCTAssertFalse(lines.isEmpty, """
                    \(state) in \(language.rawValue) at \(Int(width)) pt drew no 40 pt figure \
                    at all
                    """)
                guard lines.count > 1 else { continue }
                wrapped.append("\(language.rawValue)@\(Int(width))")
                let spread = HeroFigure.spread(lines)
                XCTAssertLessThan(spread, Self.apart, """
                    \(state) in \(language.rawValue) at \(Int(width)) pt drew its \(lines.count) \
                    figure lines on centres \(String(format: "%.2f", spread)) pt apart — \
                    \(HeroFigure.centres(lines)) — so the sentence is ragged against a column \
                    everything else in this block is centred in
                    """)
            }
        }
        // «Every wrapped line is centred» is satisfied outright by a figure that
        // never wraps, so the sweep says what it found before it is believed.
        XCTAssertFalse(wrapped.isEmpty, """
            \(state): no language wrapped its figure at either width, so this sweep proved \
            nothing about where a second line sits
            """)
    }
}
