// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import SwiftUI
import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **The block copied `KeepAwakeHero`'s placement and none of its motion, and
/// the whole page paid for it.**
///
/// Measured off the render before this landed: the section title under the hero
/// sat at five different heights across five ordinary states of one Mac, and two
/// of those transitions happen with nobody touching anything. The exit probe
/// answering moved the page 16 pt, because the country slot was 22 pt in one
/// branch and 11 in the other. Helm first learning the tunnel's uptime moved it
/// 8, because a fourth column appeared. `KeepAwakeHero`'s own comment is about
/// exactly this — «a fade that snaps the page by 20 pt underneath somebody's
/// eyes is the fade being blamed for a jump it did not cause».
@MainActor
final class AHeroThatDoesNotShoveThePageTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func tunnel(exit: VPNExitVerdict,
                        since: Date? = Date(timeIntervalSince1970: 1_700_000_000 - 4440),
                        excluded: VPNExcludedRoutes.Summary = .none) -> VPNTunnelState {
        VPNTunnelState(name: "incy", interface: "utun4", since: since,
                       bytesIn: 143_700_000, bytesOut: 19_800_000,
                       exit: exit, speed: nil, excluded: excluded)
    }

    /// The hero alone, so what is measured is the block rather than the page's
    /// own chrome around it.
    private func height(_ tunnels: [VPNTunnelState]) -> CGFloat {
        let page = ZStack {
            Color(nsColor: .windowBackgroundColor)
            VPNTunnelHero(tunnels, selected: .constant(nil), now: now,
                          measuring: nil, measure: { _ in })
                .padding(HelmSpace.s5)
        }
        let render = MountedRender(page, width: 744, height: 500, appearance: .darkAqua)
        renders.append(render)
        render.settle(30)
        return ink(render)
    }

    /// How far down the drawing carries ink — the block's drawn height, which is
    /// what moves the page under it. Read off the bitmap rather than off a
    /// layout API, because a layout API answers where the block is going and
    /// this test is about where it is.
    private func ink(_ render: MountedRender) -> CGFloat {
        let view = render.host
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return -1 }
        let scale = max(1, rep.pixelsHigh / max(1, Int(view.bounds.height)))
        let pane = (0..<3).map { Int(data[6 * rep.bytesPerRow + (rep.pixelsWide / 2) * 4 + $0]) }
        var last = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let p = y * rep.bytesPerRow + x * 4
                let d = (0..<3).map { abs(Int(data[p + $0]) - pane[$0]) }.max() ?? 0
                if d > 3 { last = y; break }
            }
        }
        return last < 0 ? -1 : CGFloat(last) / CGFloat(scale)
    }

    /// **The country arriving must not resize the page.**
    ///
    /// It is a value from the network landing in a slot the reader is looking
    /// at, and it used to change that slot's type size by 2×. Both branches are
    /// 16 pt now, and 16 is on the ladder — nothing is added to
    /// `TypeScaleRatchetTests`.
    func testTheExitProbeAnsweringDoesNotChangeTheBlocksHeight() {
        let unknown = height([tunnel(exit: .throughTunnel(countryCode: nil))])
        let named = height([tunnel(exit: .throughTunnel(countryCode: "NL"))])
        XCTAssertGreaterThan(unknown, 0, "precondition: nothing was drawn at all")
        XCTAssertEqual(named, unknown, accuracy: 2, """
            the block is \(named) pt with a country and \(unknown) pt without one, \
            so an answer arriving from the network shoves everything below it by \
            \(abs(named - unknown)) pt
            """)
    }

    /// **A second tunnel coming up must not resize the block either**, and that
    /// is a fact about the button rather than about the segments.
    ///
    /// A lone segment is dropped where a button stands beside it
    /// (`VPNTunnelSwitcher.drawn(beside:)`), so on a Mac with one tunnel the
    /// Measure button is the only thing on the row of verbs — and a `.large`
    /// bordered button is not the 30 pt the segments and the spinner beside it
    /// are. Measured with the pin taken out: 361.5 pt with one tunnel against
    /// 362.5 with two, so the page settles 1 pt higher on an ordinary Mac and
    /// drops back the moment a second tunnel connects — a move
    /// `helmMeasuredHeight` would ramp over 0.30 s rather than snap. Free to
    /// avoid, so it is avoided, and asserted **exactly**: the reading is off the
    /// same pixels twice and `accuracy: 1` swallowed the whole defect.
    func testASecondTunnelComingUpDoesNotChangeTheBlocksHeight() {
        let alone = tunnel(exit: .throughTunnel(countryCode: "NL"))
        let second = VPNTunnelState(name: "work", interface: "utun7",
                                    since: alone.since, bytesIn: alone.bytesIn,
                                    bytesOut: alone.bytesOut, exit: .besideTunnel, speed: nil)
        let one = height([alone])
        let both = height([alone, second])
        XCTAssertGreaterThan(one, 0, "precondition: nothing was drawn at all")
        XCTAssertEqual(one, both, """
            the block is \(one) pt with one tunnel and \(both) with two, so the \
            page moves \(abs(one - both)) pt when a second tunnel connects — the \
            row's controls are not one height
            """)
    }

    /// **Structural, because motion is not a value.**
    ///
    /// Whether the block ramps cannot be read off a still, and a probe that
    /// samples frames belongs to the motion harness rather than to the suite.
    /// What a test here can hold is that the constructs are present at all —
    /// the omission this file exists for was total: zero of them against
    /// `KeepAwakeHero`'s thirty.
    func testTheBlockCarriesTheMotionItsShapeRequires() throws {
        let hero = RepoSource.root
            .appendingPathComponent("Sources/Modules/VPN/UI/VPNTunnelHero.swift")
        let source = try String(contentsOf: hero, encoding: .utf8)
        for construct in ["helmMeasuredHeight", "withAnimation", ".transition(", "HelmMotion"] {
            XCTAssertTrue(source.contains(construct), """
                the hero no longer names \(construct), so it changes height under \
                the reader without animating — which is the defect it was measured \
                at five heights for
                """)
        }
        XCTAssertTrue(source.contains(".clipped()"), """
            the measured frame has no clip, so an outgoing state taller than the \
            one arriving draws past the block's edge over the page
            """)
    }

    // MARK: - What the tunnel does not carry

    /// Four sentences and no assembly. The one worth naming is Apple's network:
    /// on the machine this was written against it is excluded, so iCloud, the
    /// App Store and iMessage leave with the real address under a green tick.
    func testTheClauseNamesAppleAndSaysNothingWhenThereIsNothingToSay() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            XCTAssertNil(VPNStr.excluded(.none),
                         "\(language.rawValue): a tunnel that excludes nothing got a clause")
            let local = VPNStr.excluded(.init(localNetwork: true, apple: false, others: 0))
            let apple = VPNStr.excluded(.init(localNetwork: false, apple: true, others: 0))
            let both = VPNStr.excluded(.init(localNetwork: true, apple: true, others: 0))
            let other = VPNStr.excluded(.init(localNetwork: true, apple: false, others: 3))
            for (name, value) in [("local", local), ("apple", apple),
                                  ("both", both), ("other", other)] {
                XCTAssertNotNil(value, "\(language.rawValue): \(name) said nothing")
            }
            XCTAssertNotEqual(local, both, """
                \(language.rawValue): a tunnel that excludes Apple's whole network \
                reads the same as one that excludes a printer
                """)
            XCTAssertNotEqual(apple, both)
            XCTAssertNotEqual(local, other)
        }
    }

    /// And the clause reaches the value the view draws, rather than only
    /// existing in the string table.
    func testTheStripCarriesTheClause() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        AppLanguage.override = .en
        let bare = VPNTunnelStrip(tunnel(exit: .throughTunnel(countryCode: "NL")), now: now)
        XCTAssertNil(bare.exclusions)

        let excluded = VPNTunnelStrip(
            tunnel(exit: .throughTunnel(countryCode: "NL"),
                   excluded: .init(localNetwork: true, apple: true, others: 0)), now: now)
        XCTAssertEqual(excluded.exclusions, VPNStr.excludedLocalAndApple, """
            the summary reached the wire and stopped there, so the page still \
            tells the reader that all of this Mac's traffic goes through the tunnel
            """)
    }
}
