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

/// **An absent reading is an absent tile, never a dash.**
///
/// Helm launched after a tunnel came up did not see the moment, so there is no
/// duration to draw; a «—» in that slot is a measurement of nothing, and a
/// person reading it cannot tell it from a tunnel that has been up for no time
/// at all. The counters have the same shape one step over — nil is «the kernel
/// had no counters for this interface», which is not «it has carried nothing».
///
/// The one deliberate exception is the speed tile, and it is an exception
/// because its absence is *actionable*: there is no passive way to read a
/// link's throughput, so the tile stands with a dash and the button under it
/// says what a measurement costs.
///
/// **What the probe can and cannot see, measured before anything was written
/// on top of it.** `NSHostingView.accessibilityChildren()` is empty under this
/// suite whatever the view says — the a11y tree is built for a real client —
/// and SwiftUI draws its own text rather than through `NSTextField`, so a walk
/// of `everyView` finds three views for a screenful of words: the host, a
/// button's `_FocusRingView` and an `NSProgressIndicator`. So the strings are
/// asserted on `VPNTunnelStrip`, which is what the view draws and nothing else,
/// and the *render* is asserted on what a render can actually answer: how many
/// wells were drawn, whether a control is there, whether a spinner is. Both
/// halves matter — a strip nobody drew would pass the first alone.
@MainActor
final class TheStripDrawsOnlyWhatIsKnownTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    /// A fixed moment, so «one hour fourteen» is one hour fourteen on every run.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// The mock-up's own tunnel: up for 1 h 14 min, 1.2 GB down, 210 MB up,
    /// leaving through the Netherlands.
    private func tunnel(since: Date?,
                        bytesIn: UInt64? = 1_200_000_000,
                        bytesOut: UInt64? = 210_000_000,
                        exit: VPNExitVerdict = .throughTunnel(countryCode: "NL"),
                        speed: VPNSpeedReading? = nil) -> VPNTunnelState {
        VPNTunnelState(name: "incy", interface: "utun4", since: since,
                       bytesIn: bytesIn, bytesOut: bytesOut, exit: exit, speed: speed)
    }

    private var stamped: Date { now.addingTimeInterval(-(3600 + 14 * 60)) }

    private func strip(_ state: VPNTunnelState, measuring: Bool = false) -> VPNTunnelStrip {
        VPNTunnelStrip(state, now: now, measuring: measuring)
    }

    // Every string here is read through `AppLanguage.current`, the way `VPNStr`'s
    // own members are, so a bare assertion would only ever check whichever
    // language this Mac happens to be set to — `AppLanguage.each` is what runs
    // one in all eight and puts the app back afterwards.

    // MARK: - The render, and what it can answer

    /// The section over an opaque page, which is what it sits on: a
    /// `cacheDisplay` of a view with nothing under it draws the wells against
    /// transparency, and the run counting below reads a departure from a pane.
    private func mount(_ state: VPNTunnelState, measuring: Bool = false) -> MountedRender {
        let page = ZStack {
            Color(nsColor: .windowBackgroundColor)
            VPNTunnelHero([state], selected: .constant(nil), now: now,
                          measuring: measuring ? state.name : nil, measure: { _ in })
                .padding(HelmSpace.s5)
        }
        // 360, not 220. The block grew a headline of two 26 pt lines and a
        // segment row that is drawn at one tunnel now, and a frame that cuts the
        // columns off makes every count below read as «one column» — a probe
        // measuring the frame rather than the drawing.
        let render = MountedRender(page, width: 720, height: 360, appearance: .darkAqua)
        renders.append(render)
        render.settle(30)
        return render
    }

    /// How many **columns** the drawing holds, counted along the row of labels.
    ///
    /// **This used to count wells, and the wells are gone.** A well was one
    /// continuous fill from edge to edge, which a run of ≥ 80 pt departing from
    /// the pane found exactly; with the fills removed that probe answers 1 for
    /// every state, which is a check that cannot fail rather than a check that
    /// passes. What is left to see is the type, and the type is in columns.
    ///
    /// **The labels, and only the labels** — measured before it was written
    /// this way, because a count over every row is not a count of columns. Two
    /// rows below carry gaps as wide as the ones between columns and are not
    /// column boundaries at all: the double space in «191 ↓  60 ↑» opens 26 pt,
    /// and the em dash in «Traffic goes through the tunnel — Netherlands» opens
    /// 49 pt, so a three-column strip scored 4 on both. A label is one short
    /// word at the head of its column, so the band the labels sit in answers
    /// the question and nothing else does.
    private func columns(_ render: MountedRender) -> Int {
        let view = render.host
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8
        else { return -1 }
        let scale = max(1, rep.pixelsHigh / max(1, Int(view.bounds.height)))
        // Wider than any gap inside a word and far under the pitch of a column,
        // which is a quarter of 696 pt at its narrowest.
        let apart = 24 * scale
        /// The clusters of ink on one row: their count, with anything narrower
        /// than a label dropped.
        func clusters(inRow y: Int) -> Int {
            let row = y * rep.bytesPerRow
            // **The row's own most common colour, not the pane's.**
            //
            // Read at x = 0 this was the pane, which was right for as long as
            // the columns sat on the bare page. They sit in a well now
            // (`VPNTunnelHero.readings`), so every pixel of those rows departs
            // from the pane and the whole strip counted as one cluster of ink —
            // the probe answered 3 for a four-column drawing and reported the
            // page as broken. The modal colour is the fill whatever the fill
            // is, so one probe reads both the page and the well.
            var counts: [Int: Int] = [:]
            for x in 0..<rep.pixelsWide {
                let at = row + x * 4
                let key = Int(data[at]) << 16 | Int(data[at + 1]) << 8 | Int(data[at + 2])
                counts[key, default: 0] += 1
            }
            let modal = counts.max { $0.value < $1.value }?.key ?? 0
            let pane = [modal >> 16 & 0xFF, modal >> 8 & 0xFF, modal & 0xFF]
            var found = 0, first = -1, last = -1
            for x in 0..<rep.pixelsWide {
                let at = row + x * 4
                let far = (0..<3).map { abs(Int(data[at + $0]) - pane[$0]) }.max() ?? 0
                guard far > 2 else { continue }
                if first < 0 || x - last > apart {
                    if first >= 0, last - first >= apart { found += 1 }
                    first = x
                }
                last = x
            }
            // Measured first mark to last, never as a count of the pixels that
            // happen to be dark: for a word that is a third of the space it
            // takes, and every cluster would fall under the threshold.
            if first >= 0, last - first >= apart { found += 1 }
            return found
        }
        // **The widest spread of clusters anywhere in the drawing, rather than
        // the band the labels were assumed to be in.**
        //
        // This used to take the first row carrying ink and read twelve points
        // down from it, which was the label row exactly while the block opened
        // with the columns. It opens with a headline now, so that anchor found
        // a 26 pt sentence and answered «one column» for every state — a probe
        // measuring where the drawing starts rather than what it holds
        // (CLAUDE.md § anchor a measurement on something that moves with the
        // thing measured). Nothing else in the block splits into three pieces
        // across the width: the headline is one run, a segment is one, and the
        // button and its note sit 8 pt apart, which is inside `apart`.
        return (0..<rep.pixelsHigh).map(clusters(inRow:)).max() ?? 0
    }

    // MARK: - 1. A moment nobody saw is not a dash

    func testATunnelWhoseMomentWasNotSeenDrawsNoUptimeTile() {
        AppLanguage.each { language in
            let kinds = strip(tunnel(since: nil)).tiles.map(\.kind)
            XCTAssertFalse(kinds.contains(.uptime), """
                \(language.rawValue): a tunnel that was already up when Helm \
                launched drew an uptime tile — there is no duration to put in it
                """)
            XCTAssertTrue(kinds.contains(.speed),
                          "precondition: \(language.rawValue) drew no tiles at all")
        }
        // And on the screen: three columns where a stamped tunnel draws four.
        let seen = columns(mount(tunnel(since: stamped)))
        XCTAssertEqual(seen, 4, "precondition: the probe cannot see the columns it is counting")
        XCTAssertEqual(columns(mount(tunnel(since: nil))), 3, """
            the drawing still holds four columns with no moment to report: the \
            uptime column is being drawn empty rather than left out
            """)
    }

    // MARK: - 2. A stamped tunnel says how long

    func testAStampedTunnelDrawsItsUptime() {
        AppLanguage.each { language in
            guard let tile = strip(tunnel(since: stamped)).tiles.first(where: { $0.kind == .uptime })
            else {
                XCTFail("\(language.rawValue): no uptime tile for a tunnel Helm watched come up")
                return
            }
            XCTAssertEqual(tile.label, VPNStr.tileUptime)
            XCTAssertTrue(tile.value.contains("1") && tile.value.contains("14"), """
                \(language.rawValue) wrote one hour fourteen as «\(tile.value)»
                """)
        }
        AppLanguage.only(.ru) {
            let drawn = strip(tunnel(since: stamped))
            let tile = drawn.tiles.first { $0.kind == .uptime }
            XCTAssertEqual(tile?.value, "1 ч 14 мин")
        }
    }

    // MARK: - 3. Before a measurement

    func testBeforeAMeasurementTheSpeedTileOffersOneAndSaysWhatItCosts() {
        AppLanguage.each { language in
            let drawn = strip(tunnel(since: stamped))
            guard let tile = drawn.tiles.first(where: { $0.kind == .speed }) else {
                XCTFail("\(language.rawValue): no speed tile at all")
                return
            }
            XCTAssertEqual(tile.value, VPNTunnelStrip.noReading,
                           "\(language.rawValue): the speed tile invented a figure")
            // **The unit alone.** The price of the press moved beside the
            // press: quoted here as well it was the same clause twice on one
            // screen, and it wrapped this column to two lines while its three
            // neighbours took one.
            XCTAssertEqual(tile.note, VPNStr.speedUnit, """
                \(language.rawValue): the column quotes the button's price under a \
                figure that does not exist yet, and the button quotes it too
                """)
            XCTAssertEqual(drawn.action, .offer(VPNStr.measureSpeed))
        }
    }

    // MARK: - 4. After one

    func testAfterAMeasurementTheFigureIsDrawnWithItsAge() {
        let taken = now.addingTimeInterval(-180)
        let reading = VPNSpeedReading(down: 212, up: 95, rpm: 340, at: taken)
        AppLanguage.each { language in
            let drawn = strip(tunnel(since: stamped, speed: reading))
            guard let tile = drawn.tiles.first(where: { $0.kind == .speed }) else {
                XCTFail("\(language.rawValue): no speed tile at all")
                return
            }
            XCTAssertTrue(tile.value.contains("212") && tile.value.contains("95"), """
                \(language.rawValue) drew the reading as «\(tile.value)»
                """)
            // **`.short`, which is an argument rather than a restatement.** The
            // tile drew the full form until the owner reported «1 минуту назад»
            // wrapping a 119 pt column, so this line fails in six of the eight
            // if the style is dropped from the call — Japanese and Chinese spell
            // the two the same and cannot tell them apart at all.
            XCTAssertEqual(tile.note,
                           VPNStr.speedNote(HelmDates.relative(taken, to: now, style: .short)),
                           """
                           \(language.rawValue): a figure three minutes old is drawn \
                           without its age, which reads as the link's speed now
                           """)

            XCTAssertEqual(drawn.action, .offer(VPNStr.measureAgain),
                           "\(language.rawValue): the button still offers a first measurement")
        }
    }

    /// **A four-digit link is where the app's own number formatting shows.**
    ///
    /// The figure was interpolated through `Decimal(speed.down)`, which looks
    /// like `HelmUI`'s member and is not: that one takes a `Double`, `down` is
    /// an `Int`, Swift will not convert a variable — so the call bound to
    /// `Foundation.Decimal.init(_: Int)` and the tile drew that type's
    /// locale-independent `description`. Invisible at three digits and wrong at
    /// four, where a 10 Gbit link drew «10000» and every other number on the
    /// page is grouped the way the language groups digits.
    func testAFourDigitReadingIsGroupedTheWayTheLanguageGroupsDigits() {
        let reading = VPNSpeedReading(down: 10_000, up: 4_200, rpm: 340,
                                      at: now.addingTimeInterval(-5))
        AppLanguage.each { language in
            let tile = strip(tunnel(since: stamped, speed: reading)).tiles
                .first { $0.kind == .speed }
            XCTAssertEqual(tile?.label, VPNStr.tileSpeed,
                           "precondition: \(language.rawValue) drew no speed tile at all")
            XCTAssertTrue(tile?.value.contains(Count(10_000)) == true, """
                \(language.rawValue) drew «\(tile?.value ?? "")», where the \
                language writes «\(Count(10_000))»
                """)
        }
    }

    /// The other half of the same rule, and the reader `speedIsStale` was
    /// written for: a reading taken a moment ago **is** the link's speed now,
    /// so it stands without an age under it.
    func testAFreshReadingStandsWithoutAnAge() {
        let reading = VPNSpeedReading(down: 212, up: 95, rpm: 340,
                                      at: now.addingTimeInterval(-5))
        AppLanguage.each { language in
            let tile = strip(tunnel(since: stamped, speed: reading)).tiles
                .first { $0.kind == .speed }
            // The absence below passes for free on a strip that drew nothing.
            XCTAssertEqual(tile?.label, VPNStr.tileSpeed,
                           "precondition: \(language.rawValue) drew no speed tile at all")
            XCTAssertEqual(tile?.note, VPNStr.speedUnit, """
                \(language.rawValue): a five-second-old reading carries an age \
                line — «\(tile?.note ?? "")». The note is the unit and nothing \
                else here; it is not absent, because every column has one.
                """)
        }
    }

    // MARK: - 4b. One shape for the row

    /// **Every column carries a note, and that is the row's shape.**
    ///
    /// Three of the four had none: the figures sat over nothing while the
    /// speed column carried a line, so the row was three columns of one height
    /// and a fourth of another. The notes are what the wells used to be — the
    /// thing that makes four columns read as one row — now that there is no
    /// fill behind them.
    func testEveryColumnCarriesANote() {
        let reading = VPNSpeedReading(down: 212, up: 95, rpm: 340, at: now.addingTimeInterval(-5))
        AppLanguage.each { language in
            let drawn = strip(tunnel(since: stamped, speed: reading))
            XCTAssertEqual(drawn.tiles.count, 4,
                           "precondition: \(language.rawValue) drew \(drawn.tiles.count) columns, "
                           + "so the notes below are not a row")
            for tile in drawn.tiles {
                XCTAssertFalse(tile.note.isEmpty, """
                    \(language.rawValue): the \(tile.kind.rawValue) column has no note, so it \
                    is a column of a different height beside three that are not
                    """)
            }
        }
    }

    /// The name left the heading and landed here, beside the interface — the
    /// one place on the page where «which tunnel» belongs to the row it is
    /// about rather than to a title three lines above it.
    func testTheFirstColumnNamesTheTunnelAndItsInterface() {
        AppLanguage.each { language in
            let drawn = strip(tunnel(since: stamped))
            let tile = drawn.tiles.first { $0.kind == .uptime }
            XCTAssertEqual(tile?.label, VPNStr.tileUptime,
                           "precondition: \(language.rawValue) drew no uptime column at all")
            XCTAssertEqual(tile?.note, VPNStr.tunnelAndInterface("incy", "utun4"), """
                \(language.rawValue) wrote «\(tile?.note ?? "")» where the tunnel this row \
                is about is named nowhere on the page
                """)
            // And nothing above it names the tunnel either: the heading that
            // used to sit 40 pt away is gone with the section, and what stands
            // there now is the verdict — a sentence about the traffic, not
            // about a configuration.
            XCTAssertFalse(drawn.verdict.contains("incy"),
                           "\(language.rawValue): the verdict names the tunnel, which the "
                           + "first column already does")
        }
    }

    /// A total needs its span. Both byte columns, in one assertion, because
    /// they are the same reading in two directions and a note on one alone
    /// would read as a difference between them.
    func testBothByteColumnsSayWhatSpanTheyAreATotalOver() {
        AppLanguage.each { language in
            let drawn = strip(tunnel(since: stamped))
            for kind in [VPNTunnelStrip.Reading.down, .up] {
                let tile = drawn.tiles.first { $0.kind == kind }
                XCTAssertEqual(tile?.note, VPNStr.bytesSince, """
                    \(language.rawValue): the \(kind.rawValue) figure is a total over \
                    nothing the reader is told about
                    """)
            }
        }
    }

    /// **One grammar for units in one row.** «129.4 MB» carries its unit in the
    /// value and «Speed, Mbit/s» carried its own in the label, which is the same
    /// question answered two ways three columns apart. The speed column's value
    /// is two numbers and cannot hold a unit, so the unit went to the note and
    /// the label became a plain word like the other three.
    func testTheSpeedLabelIsAPlainWordAndTheUnitIsInTheNote() {
        let reading = VPNSpeedReading(down: 212, up: 95, rpm: 340, at: now.addingTimeInterval(-5))
        AppLanguage.each { language in
            for state in [tunnel(since: stamped), tunnel(since: stamped, speed: reading)] {
                let tile = strip(state).tiles.first { $0.kind == .speed }
                XCTAssertEqual(tile?.label, VPNStr.tileSpeed,
                               "precondition: \(language.rawValue) drew no speed column")
                XCTAssertFalse(tile?.label.contains(VPNStr.speedUnit) == true, """
                    \(language.rawValue) put the unit back in the label — «\(tile?.label ?? "")» \
                    beside a byte figure that carries its own
                    """)
                XCTAssertTrue(tile?.note.hasPrefix(VPNStr.speedUnit) == true, """
                    \(language.rawValue) drew the note as «\(tile?.note ?? "")», which names \
                    no unit for two bare numbers
                    """)
            }
        }
    }

    // MARK: - 5. The verdict is words, not a colour

    func testTrafficGoingRoundTheTunnelIsSaidInWords() {
        AppLanguage.each { language in
            let drawn = strip(tunnel(since: stamped, exit: .besideTunnel))
            XCTAssertEqual(drawn.verdict, VPNStr.trafficBesideTunnel, """
                \(language.rawValue): the one outcome this check exists to \
                catch is not written down
                """)
            // …and it is not the same sentence as the two it must never be
            // read as.
            XCTAssertNotEqual(drawn.verdict,
                              strip(tunnel(since: stamped, exit: .unknown)).verdict)
            XCTAssertNotEqual(drawn.verdict,
                              strip(tunnel(since: stamped,
                                           exit: .throughTunnel(countryCode: nil))).verdict)
        }
    }

    /// A probe that failed is not the bad news.
    ///
    /// Both cases above checked a `mark` as well as a sentence — a glyph the
    /// headline wore beside its words — until the two heroes converged and the
    /// glyph went. It was `accessibilityHidden` because the sentence already
    /// said what it said, so it carried colour and nothing else, and it moved
    /// the sentence 16.25 pt off the axis of its own caption doing it
    /// (`VPNTunnelHero.headline`). The section's title was already the rule.
    func testAnUncheckedExitIsNeitherVerdict() {
        AppLanguage.only(.en) {
            let drawn = strip(tunnel(since: stamped, exit: .unknown))
            XCTAssertEqual(drawn.verdict, VPNStr.trafficUnknown)
        }
    }

    /// **The verdict is the same sentence whatever the country is**, because it
    /// answers a different question from the country's own.
    ///
    /// It carried the place as its tail until the strip became the page's hero,
    /// and the two facts are now two lines: this one is «is my traffic in the
    /// tunnel», which is true or false before anybody has been told where the
    /// traffic comes out.
    func testTheVerdictSaysNothingAboutThePlace() {
        AppLanguage.each { language in
            for code in ["NL", "XX", nil] {
                XCTAssertEqual(strip(tunnel(since: stamped,
                                            exit: .throughTunnel(countryCode: code))).verdict,
                               VPNStr.trafficThroughTunnel,
                               "\(language.rawValue): the verdict changed with the country")
            }
        }
    }

    /// **A country that does not resolve is `unknown`, never a named nothing.**
    ///
    /// Three states and not an optional string: a code `Locale` cannot name and
    /// a probe that has not answered are the same news to the reader — Helm
    /// does not know — and both are different from «there is no exit country to
    /// be about», which is what the other two verdicts are.
    func testAPlaceIsNamedOnlyWhenItIsKnown() {
        AppLanguage.only(.en) {
            XCTAssertEqual(strip(tunnel(since: stamped,
                                        exit: .throughTunnel(countryCode: "NL"))).place,
                           .named(VPNStr.country("NL") ?? ""))
            XCTAssertEqual(strip(tunnel(since: stamped,
                                        exit: .throughTunnel(countryCode: "XX"))).place,
                           .unknown, "a code Locale cannot name was drawn as a place")
            XCTAssertEqual(strip(tunnel(since: stamped,
                                        exit: .throughTunnel(countryCode: nil))).place,
                           .unknown, "a probe that never answered was drawn as a place")
        }
    }

    /// And the two verdicts that are not about an exit carry no place at all.
    /// «The exit country is not known» beside «Traffic is not going through the
    /// tunnel» would be answering a question the reader has not reached.
    func testAVerdictThatIsNotAboutAnExitCarriesNoPlace() {
        AppLanguage.only(.en) {
            XCTAssertEqual(strip(tunnel(since: stamped, exit: .besideTunnel)).place, VPNTunnelStrip.Place.none)
            XCTAssertEqual(strip(tunnel(since: stamped, exit: .unknown)).place, VPNTunnelStrip.Place.none)
        }
    }

    // MARK: - 6. While it runs

    /// **The arc is drawn against this link's own last run, and it was drawn
    /// against a constant in a view.**
    ///
    /// 22 s, taken on one Mac on one link on one afternoon, with the view's own
    /// comment saying it should not be a constant at all. It is not one now: the
    /// port times its run and the reading carries the length, so a link that
    /// takes 31 s is drawn against 31.
    ///
    /// Still a length rather than a stage — the engine knows only whether a run
    /// is in flight — which is why this is one number on a value and not a
    /// progress report.
    func testTheWaitIsDrawnAgainstThisLinksOwnLastRun() {
        let measured = VPNSpeedReading(down: 212, up: 95, rpm: 340,
                                       at: now.addingTimeInterval(-5), took: 31)
        XCTAssertEqual(strip(tunnel(since: stamped, speed: measured)).expectedWait, 31, """
            the page draws its arc against a number somebody typed rather than \
            against the run this Mac actually took
            """)
    }

    /// And before this Mac has ever measured its own link — or after an update
    /// from a build whose readings carried no length — the fallback is the
    /// figure the port was measured at, in the one place it is written down.
    func testWithNoRunToGoOnTheWaitIsTheMeasuredTypicalOne() {
        XCTAssertEqual(strip(tunnel(since: stamped)).expectedWait,
                       NetworkQualitySpeed.typicalRun,
                       "a Mac that has never measured is drawn against nothing")
        let untimed = VPNSpeedReading(down: 212, up: 95, rpm: 340, at: now)
        XCTAssertEqual(strip(tunnel(since: stamped, speed: untimed)).expectedWait,
                       NetworkQualitySpeed.typicalRun, """
            a reading decoded from a payload written before the length existed \
            has no length, and the arc is drawn against nil
            """)
    }

    /// **The slot is worn by the run, not by the page.**
    ///
    /// `isMeasuring` is read off `action` rather than stored beside it, so the
    /// two cannot disagree — and the row asks it once per card, so a second
    /// field meaning the same thing would be a field somebody has to remember
    /// to set in three places.
    func testTheStripSaysWhenARunIsInFlight() {
        XCTAssertTrue(strip(tunnel(since: stamped), measuring: true).isMeasuring)
        XCTAssertFalse(strip(tunnel(since: stamped)).isMeasuring,
                       "a quiet tunnel wears the measuring slot, which says a "
                       + "figure is on its way when none is")
        XCTAssertFalse(strip(tunnel(since: stamped, exit: .besideTunnel)).isMeasuring, """
            a tunnel with no button to press is drawn as though a run were going \
            on it, and no run can be
            """)
    }

    func testWhileMeasuringTheButtonIsGoneAndTheWordIsThere() {
        AppLanguage.each { language in
            let drawn = strip(tunnel(since: stamped), measuring: true)
            XCTAssertEqual(drawn.action, .running(VPNStr.measuring), """
                \(language.rawValue): the button is still offered while a run \
                is in flight, so a second press starts a second fifteen seconds
                """)
        }
        // On the screen: the control is gone and a spinner stands in its place.
        // One control, and none while the run is in flight — a lone tunnel's
        // segment is not drawn beside a button (`VPNTunnelSwitcher.drawn(beside:)`),
        // so the Measure button is the only control this state has.
        let quiet = mount(tunnel(since: stamped))
        XCTAssertEqual(quiet.host.everyView(named: "_FocusRingView").count, 1,
                       "precondition: the probe cannot see the button it is looking for")
        XCTAssertTrue(quiet.host.everyView(ofType: NSProgressIndicator.self).isEmpty,
                      "precondition: something is already spinning with no run in flight")

        let running = mount(tunnel(since: stamped), measuring: true)
        XCTAssertEqual(running.host.everyView(named: "_FocusRingView").count, 0,
                       "the button is still on the screen while a measurement runs")
        XCTAssertEqual(running.host.everyView(ofType: NSProgressIndicator.self).count, 1,
                       "no spinner stands where the button was")
    }

    // MARK: - 7. A run the port refused

    /// **The clearing rule has to be true of every ending a run can have.**
    ///
    /// Comparing the speed before and after is true of none of the awkward
    /// ones: a run answering the same figure as last time would leave the
    /// spinner turning for ever, and a run the port refused — a `-1009`, a
    /// killed tool — never changes `speed` at all. So the rule is the arrival
    /// itself: the engine writes the result, refusal included, and emits, and
    /// **any state that arrives ends the run**.
    func testARunThePortRefusedStopsTheSpinner() {
        let transport = LocalTransport()
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let vm = VPNViewModel(transport: transport, settings: VPNSettings(store: store))
        vm.measureSpeed("incy")
        XCTAssertEqual(vm.measuring, "incy", "precondition: the press never started a run")

        // What the engine writes when the tool answered nothing: the state it
        // already had, with `speed` still nil.
        let payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: "incy", status: .connected, kind: "IKEv2")],
            autoConnected: [], defaultName: "incy", lastAutomation: nil,
            tunnels: [tunnel(since: stamped)])
        transport.emit(EngineEvent(name: VPNEvent.state.rawValue,
                                   payload: try! JSONEncoder().encode(payload)))
        for _ in 0..<80 where vm.tunnels.isEmpty {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(vm.tunnels.isEmpty,
                       "the wire did not deliver: the reading below would be of nothing")
        XCTAssertNil(vm.tunnels.first?.speed, "precondition: this is the run that answered nothing")
        XCTAssertNil(vm.measuring, """
            a refused run left the spinner turning: nothing about the state \
            changed, so a rule that watches the figure never fires
            """)
    }
}
