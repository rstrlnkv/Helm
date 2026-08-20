// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// A reading that could not be taken at all, so a broken bench fails loudly
/// rather than handing back an empty list every assertion below is happy with.
private struct CardReadFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// **«What makes them read as one row is that every column has the same three
/// lines» — and nothing in the code held it.**
///
/// `VPNTunnelHero.readings`' own doc comment said that, and it was true only
/// while every note was one line. Measured on the page before this file existed,
/// at the narrowest pane the window allows: 76 / 94 / 94 / 81, so two of the four
/// stand 13 pt proud of the card beside them and the first stands 5 pt short of
/// all of them. A long configuration name — «NBCom VPN Office Frankfurt», which
/// is ARCHITECTURE's own example of an ordinary one — breaks the family from the
/// other end, at every pane.
///
/// The fix is one line of SwiftUI (`maxHeight: .infinity` on the card's own
/// stack, under the row's `.fixedSize`), which is an idiom rather than a
/// contract: exactly the kind of thing a later edit reorders without noticing,
/// and exactly the kind of thing no value can be read for. So it is guarded off
/// the drawing.
///
/// **The page, not a bench beside it.** A hero mounted alone is handed whatever
/// width the test picks, and the first version of this file picked one 100 pt
/// narrower than the page gives — every number it produced was about a window
/// nobody has. `VPNSettingsPage` is mounted whole here, at the three pane widths
/// `SettingsWindow` can actually produce.
@MainActor
final class TheReadingsAreOneRowTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    // MARK: - The three panes the window can produce

    /// A width of the pane the page is drawn in, and the geometry that follows
    /// from it.
    ///
    /// **Not window widths, and the difference is 214 pt.** `SettingsWindow`
    /// holds a split view: `contentMinSize` is 860 wide and the sidebar is
    /// 180…320 with 214 as its default, so the page gets 645 at the narrowest
    /// ordinary window, 539 at the narrowest window with the widest sidebar, and
    /// anything upward of that — where the settings column's own 744 pt cap
    /// takes over and the row stops growing. Those are the three, and the
    /// narrowest is the one that breaks.
    private struct Pane {
        let width: CGFloat
        /// What a grouped `Form`'s section gets, which is what the row spans.
        var content: CGFloat { min(width, HelmLayout.settingsColumn) - HelmLayout.formInset * 2 }
        /// One card: the row less its three gaps, in quarters.
        var card: CGFloat { (content - 3 * HelmSpace.s5) / 4 }
        /// Bare pane between the window's edge and the row, each side. Where the
        /// colour of «nothing drawn» is read from, and where the scan starts —
        /// past the 744 pt cap this strip is partly unpainted rather than pane,
        /// and the two are different colours.
        var gutter: CGFloat { (width - content) / 2 }
    }

    private let panes = [Pane(width: 845), Pane(width: 645), Pane(width: 539)]

    // MARK: - The states drawn

    /// **Stamped off the real clock, and it has to be.** `VPNSettingsPage`
    /// builds its hero with `now: Date()` — the page has no seam for a fixed
    /// one — so a reading dated from a frozen 2023 is a reading three years old
    /// whatever the test calls it. The first version of this file used a fixed
    /// stamp, which made the «fresh» render stale too and left
    /// `testAReadingGoingStaleDoesNotMoveTheRow` comparing one state against
    /// itself: green, and about nothing.
    private func tunnel(name: String = "incy", interface: String = "utun8",
                        speed: VPNSpeedReading? = nil) -> VPNTunnelState {
        VPNTunnelState(name: name, interface: interface,
                       since: Date().addingTimeInterval(-(3600 + 14 * 60)),
                       bytesIn: 143_700_000, bytesOut: 19_800_000,
                       exit: .throughTunnel(countryCode: "NL"), speed: speed)
    }

    /// A four-digit reading, which is the case `helmMetricFigure` shrinks first.
    private func reading(secondsOld: TimeInterval) -> VPNSpeedReading {
        VPNSpeedReading(down: 1176, up: 298, rpm: 340,
                        at: Date().addingTimeInterval(-secondsOld))
    }

    // MARK: - Reading the drawing

    /// One card fill, in points from the top left of the page.
    ///
    /// Found in the bitmap rather than in the view tree, and it has to be: the
    /// four cards are `RoundedRectangle().fill()` drawn straight into the
    /// parent's layer, so — unlike a settings section — there is no `NSView`
    /// with a frame to read.
    /// One pixel's colour, and how far it is from another's.
    private struct Pixel {
        let red: Int
        let green: Int
        let blue: Int

        init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            self.red = Int(red)
            self.green = Int(green)
            self.blue = Int(blue)
        }

        /// Two, not three: the card is `Color.primary.opacity(0.05)`, about
        /// eleven of 255 against the pane, and a tolerance tuned for
        /// antialiased type reads the fill as empty.
        func departs(from pane: Pixel) -> Bool {
            abs(red - pane.red) > 2 || abs(green - pane.green) > 2 || abs(blue - pane.blue) > 2
        }
    }

    private struct Card: Equatable {
        let left: Int
        let right: Int
        let top: Int
        let bottom: Int
        var height: Int { bottom - top + 1 }
        var width: Int { right - left + 1 }
    }

    /// **The row is found by its own shape, not by where it happens to sit.**
    ///
    /// Four fills, side by side, all one width: nothing else the page draws is
    /// that, and looking for the shape means no row number is typed here — which
    /// is the cost `TheConnectionsLineUpWithTheCardsTests` records for a row that
    /// was.
    ///
    /// - Parameter pane: the geometry, for where the pane's own colour is read.
    ///   Per row and from the gutter, never from the top-left pixel: that pixel
    ///   is the window background on a bench and the *transparent* strip beside
    ///   the settings column on the page, and reading it there made every row of
    ///   the window measure as one enormous field. `RenderedField`'s header
    ///   records the same reading being confident and wrong for the same reason.
    private func cards(_ render: MountedRender, _ pane: Pane) throws -> [Card] {
        let view = render.host
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.bitmapData)
        XCTAssertEqual(rep.samplesPerPixel, 4)
        let scale = max(1, rep.pixelsHigh / max(1, Int(view.bounds.height)))
        let sample = (Int(pane.gutter) - 6) * scale
        let edge = (Int(pane.gutter) - 2) * scale
        /// The pane's own colour on this row, as three stored channels rather
        /// than an array: this is read once a pixel over about two million of
        /// them per render, and the first version's `map` into a fresh `[Int]`
        /// made the file take four times as long as the page it photographs.
        func bare(_ y: Int) -> Pixel {
            let at = y * rep.bytesPerRow + sample * 4
            return Pixel(data[at], data[at + 1], data[at + 2])
        }
        func drawn(_ x: Int, _ y: Int, _ pane: Pixel) -> Bool {
            let at = y * rep.bytesPerRow + x * 4
            return Pixel(data[at], data[at + 1], data[at + 2]).departs(from: pane)
        }
        /// The maximal runs of drawn pixels on one row, inside the gutters.
        /// Given up on past five, since every caller wants exactly four.
        func runs(_ y: Int) -> [ClosedRange<Int>] {
            let pane = bare(y)
            var out: [ClosedRange<Int>] = []
            var start = -1
            for x in edge...(rep.pixelsWide - edge) {
                let on = x < rep.pixelsWide - edge && drawn(x, y, pane)
                if on, start < 0 { start = x }
                if !on, start >= 0 {
                    out.append(start...(x - 1))
                    start = -1
                    if out.count > 4 { return out }
                }
            }
            return out
        }
        /// Four fills of one width, each wide enough to be a card rather than a
        /// word: 40 pt is under the narrowest card the window can produce (116)
        /// and over the longest run a line of 10 pt type makes between spaces.
        func fourAcross(_ y: Int) -> [ClosedRange<Int>]? {
            let found = runs(y)
            guard found.count == 4, found.allSatisfy({ $0.count >= 40 * scale }),
                  let widest = found.map(\.count).max(),
                  let narrowest = found.map(\.count).min(),
                  widest - narrowest <= 2 * scale
            else { return nil }
            return found
        }

        var top = -1
        for y in 0..<rep.pixelsHigh where fourAcross(y) != nil { top = y; break }
        guard top >= 0 else {
            throw CardReadFailure("no row of four card fills anywhere on the page")
        }
        // Past the corner radius, where every card is at its full width — and
        // never past the shortest card's own bottom, which is where the row
        // stops being four fills.
        let acrossAt = min(top + Int(HelmRadius.card + 2) * scale, rep.pixelsHigh - 1)
        guard let columns = fourAcross(acrossAt) else {
            throw CardReadFailure("the row of four fills is shallower than a card's corner")
        }
        return columns.map { column in
            let middle = (column.lowerBound + column.upperBound) / 2
            var bottom = top
            for y in top..<rep.pixelsHigh {
                guard drawn(middle, y, bare(y)) else { break }
                bottom = y
            }
            return Card(left: column.lowerBound / scale, right: column.upperBound / scale,
                        top: top / scale, bottom: bottom / scale)
        }
    }

    /// The VPN page, drawn at one pane width with one tunnel up.
    private func row(_ pane: Pane, _ tunnel: VPNTunnelState) throws -> [Card] {
        let transport = LocalTransport()
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let vm = VPNViewModel(transport: transport, settings: VPNSettings(store: store))
        var payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: tunnel.name,
                                        status: .connected, kind: "IKEv2")],
            autoConnected: [], defaultName: nil, lastAutomation: nil)
        payload.tunnels = [tunnel]
        transport.emit(EngineEvent(name: "state", payload: try JSONEncoder().encode(payload)))
        for _ in 0..<50 where vm.connections.isEmpty {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let render = MountedRender(VPNSettingsPage(vm: vm, store: store),
                                   width: pane.width, height: 640, appearance: .darkAqua)
        renders.append(render)
        render.settle(20)
        return try cards(render, pane)
    }

    // MARK: - 1. The row is where this file thinks it is

    /// **The reading is checked against the geometry before anything is claimed
    /// about it.** A scan that finds four fills of the wrong width has found
    /// something else, and every assertion below would then be about that.
    func testTheFourFillsFoundAreTheReadingsRow() throws {
        for pane in panes {
            let found = try row(pane, tunnel())
            XCTAssertEqual(found.count, 4, "at \(Int(pane.width)) pt: \(found.count) fills")
            for (index, card) in found.enumerated() {
                XCTAssertEqual(CGFloat(card.width), pane.card, accuracy: 2, """
                    at \(Int(pane.width)) pt card \(index + 1) is \(card.width) pt \
                    where the settings column gives it \(pane.card) — the scan is \
                    reading something other than the readings row
                    """)
            }
            XCTAssertEqual(Set(found.map(\.top)).count, 1, """
                at \(Int(pane.width)) pt the four cards do not share a top edge, \
                so they are not one row at all: \(found.map(\.top))
                """)
        }
    }

    // MARK: - 2. Four cards, one height

    /// **The rule the row's own doc comment claims.**
    ///
    /// Every language, every pane, and both the short configuration name and the
    /// long one — the row breaks in a different cell of that table for each, and
    /// a check that ran one cell would have been green for the case the owner
    /// reported.
    func testEveryCardInTheRowStandsTheSameHeight() throws {
        for pane in panes {
            for name in ["incy", "NBCom VPN Office Frankfurt"] {
                var broken: [String] = []
                AppLanguage.each { language in
                    guard let cards = try? row(pane, tunnel(name: name,
                                                            speed: reading(secondsOld: 5)))
                    else { return XCTFail("\(language.rawValue): the page drew no row") }
                    let heights = cards.map(\.height)
                    if Set(heights).count > 1 { broken.append("\(language.rawValue) \(heights)") }
                }
                XCTAssertTrue(broken.isEmpty, """
                    at \(Int(pane.width)) pt with «\(name)» the four readings are \
                    not one row: \(broken.joined(separator: ", ")) — a card standing \
                    proud of its neighbours is what the row's own comment says \
                    cannot happen
                    """)
            }
        }
    }

    // MARK: - 3. Nothing moves on the clock alone

    /// **The 13 pt that moved with nobody touching anything.**
    ///
    /// A reading goes stale at `VPNTunnelFacts.speedGoesStaleAfter` and the note
    /// then takes its age. Measured on the page before this landed: at 645 pt in
    /// Russian «1 минуту назад» wrapped the note, grew the card from 81 pt to 94,
    /// and dropped the whole page below it by 13 at t+60 with the reader's hands
    /// nowhere near the Mac. Equal heights makes that worse rather than better —
    /// the jump moves all four cards instead of one — so the decision had to be
    /// taken in the same pass as the row.
    ///
    /// **The decision is that the short form is the whole fix, and nothing is
    /// reserved.** «1 мин. назад» is 55 pt against «1 минуту назад»'s 120, and
    /// the widest age any of the eight can print joins to 115 pt against the
    /// 119 the note has at 645 — so the note stays one line where it was one
    /// line. A reserved second line was drawn and rejected by measuring: it
    /// costs 13 pt of every card at every pane, for ever, against a jump that
    /// this removes outright. What keeps that honest is the age asked for below.
    func testNoAgeThisReadingCanShowMovesTheRow() throws {
        for pane in panes {
            var moved: [String] = []
            AppLanguage.each { language in
                let widest = widestAge(language)
                guard let fresh = try? row(pane, tunnel(speed: reading(secondsOld: 5))),
                      let stale = try? row(pane, tunnel(speed: reading(secondsOld: widest))),
                      let young = fresh.map(\.height).max(),
                      let old = stale.map(\.height).max()
                else { return XCTFail("\(language.rawValue): the page drew no row") }
                if young != old {
                    moved.append("\(language.rawValue) \(young)→\(old) at «\(age(widest, language))»")
                }
            }
            XCTAssertTrue(moved.isEmpty, """
                at \(Int(pane.width)) pt the row changes height when the reading \
                takes its age: \(moved.joined(separator: ", ")) — which is the page \
                dropping under somebody who is only looking at it
                """)
        }
    }

    /// **The oldest-*looking* reading a language can print, not the oldest one.**
    ///
    /// A test that asked only about the threshold would be asking about
    /// «1 мин. назад», which is nobody's worst case: the widest short form is
    /// «40 мин. назад» in Russian and «vor 11 Monaten» in German, and both are
    /// ages an ordinary reading reaches by being left alone. Line count does not
    /// fall as a string widens, so the widest string is the worst case and the
    /// threshold is covered by it.
    private func widestAge(_ language: AppLanguage) -> TimeInterval {
        // Every unit the formatter has, and the longest count inside each: it
        // spells eleven months differently from one, and forty minutes
        // differently from five.
        let boundaries: [TimeInterval] = [61, 5 * 60, 11 * 60, 40 * 60, 59 * 60,
                                          3600, 11 * 3600, 23 * 3600,
                                          86_400, 6 * 86_400, 604_800, 4 * 604_800,
                                          2_629_800, 11 * 2_629_800,
                                          31_557_600, 11 * 31_557_600]
        let font = NSFont.systemFont(ofSize: 10)
        func drawnWidth(_ seconds: TimeInterval) -> CGFloat {
            (age(seconds, language) as NSString).size(withAttributes: [.font: font]).width
        }
        return boundaries.max { drawnWidth($0) < drawnWidth($1) } ?? 61
    }

    private func age(_ seconds: TimeInterval, _ language: AppLanguage) -> String {
        let now = Date()
        return HelmDates.relative(now.addingTimeInterval(-seconds), to: now,
                                  style: .short, language: language.rawValue)
    }
}
