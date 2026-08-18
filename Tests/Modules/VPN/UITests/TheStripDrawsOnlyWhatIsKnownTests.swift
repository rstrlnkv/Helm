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

    /// Every string here is read through `AppLanguage.current`, the way
    /// `VPNStr`'s own members are, so a bare assertion would only ever check
    /// whichever language this Mac happens to be set to.
    private func inEachLanguage(_ body: (AppLanguage) -> Void) {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            body(language)
        }
    }

    private func inLanguage(_ language: AppLanguage, _ body: () -> Void) {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        AppLanguage.override = language
        body()
    }

    // MARK: - The render, and what it can answer

    /// The section over an opaque page, which is what it sits on: a
    /// `cacheDisplay` of a view with nothing under it draws the wells against
    /// transparency, and the run counting below reads a departure from a pane.
    private func mount(_ state: VPNTunnelState, measuring: Bool = false) -> MountedRender {
        let page = ZStack {
            Color(nsColor: .windowBackgroundColor)
            VPNTunnelSection(state, now: now, measuring: measuring, measure: {})
                .padding(HelmSpace.s5)
        }
        let render = MountedRender(page, width: 720, height: 220, appearance: .darkAqua)
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
            // The pane's own colour on this row, read at the very edge — the
            // section is padded, so x = 0 is never inside a column.
            let pane = (0..<3).map { Int(data[row + $0]) }
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
        // The labels are the first thing drawn — this view opens with the row
        // of columns, its heading having moved to the page — so the band is
        // found rather than written down: the first row carrying ink, and the
        // line of type it belongs to.
        guard let top = (0..<rep.pixelsHigh).first(where: { clusters(inRow: $0) > 0 })
        else { return 0 }
        return (top..<min(rep.pixelsHigh, top + 12 * scale)).map(clusters(inRow:)).max() ?? 0
    }

    // MARK: - 1. A moment nobody saw is not a dash

    func testATunnelWhoseMomentWasNotSeenDrawsNoUptimeTile() {
        inEachLanguage { language in
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
        inEachLanguage { language in
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
        inLanguage(.ru) {
            let tile = strip(tunnel(since: stamped)).tiles.first { $0.kind == .uptime }
            XCTAssertEqual(tile?.value, "1 ч 14 мин")
        }
    }

    // MARK: - 3. Before a measurement

    func testBeforeAMeasurementTheSpeedTileOffersOneAndSaysWhatItCosts() {
        inEachLanguage { language in
            let drawn = strip(tunnel(since: stamped))
            guard let tile = drawn.tiles.first(where: { $0.kind == .speed }) else {
                XCTFail("\(language.rawValue): no speed tile at all")
                return
            }
            XCTAssertEqual(tile.value, VPNTunnelStrip.noReading,
                           "\(language.rawValue): the speed tile invented a figure")
            XCTAssertEqual(tile.note, VPNStr.speedNote(VPNStr.speedNotYet), """
                \(language.rawValue): the column does not say what a measurement \
                costs, so the button under it asks for fifteen seconds and some \
                traffic without saying so
                """)
            XCTAssertEqual(drawn.action, .offer(VPNStr.measureSpeed))
        }
    }

    // MARK: - 4. After one

    func testAfterAMeasurementTheFigureIsDrawnWithItsAge() {
        let taken = now.addingTimeInterval(-180)
        let reading = VPNSpeedReading(down: 212, up: 95, rpm: 340, at: taken)
        inEachLanguage { language in
            let drawn = strip(tunnel(since: stamped, speed: reading))
            guard let tile = drawn.tiles.first(where: { $0.kind == .speed }) else {
                XCTFail("\(language.rawValue): no speed tile at all")
                return
            }
            XCTAssertTrue(tile.value.contains("212") && tile.value.contains("95"), """
                \(language.rawValue) drew the reading as «\(tile.value)»
                """)
            XCTAssertEqual(tile.note, VPNStr.speedNote(HelmDates.relative(taken, to: now)), """
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
        inEachLanguage { language in
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
        inEachLanguage { language in
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
        inEachLanguage { language in
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
        inEachLanguage { language in
            let tile = strip(tunnel(since: stamped)).tiles.first { $0.kind == .uptime }
            XCTAssertEqual(tile?.label, VPNStr.tileUptime,
                           "precondition: \(language.rawValue) drew no uptime column at all")
            XCTAssertEqual(tile?.note, VPNStr.tunnelAndInterface("incy", "utun4"), """
                \(language.rawValue) wrote «\(tile?.note ?? "")» where the tunnel this row \
                is about is named nowhere on the page
                """)
            // And the heading it left does not name it either — which is true
            // by construction, `VPNStr.thisTunnel` taking no tunnel, and worth
            // one line here because the page draws the two of them 40 pt apart.
            XCTAssertFalse(VPNStr.thisTunnel.contains("incy"))
        }
    }

    /// A total needs its span. Both byte columns, in one assertion, because
    /// they are the same reading in two directions and a note on one alone
    /// would read as a difference between them.
    func testBothByteColumnsSayWhatSpanTheyAreATotalOver() {
        inEachLanguage { language in
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
        inEachLanguage { language in
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
        inEachLanguage { language in
            let drawn = strip(tunnel(since: stamped, exit: .besideTunnel))
            XCTAssertEqual(drawn.verdict, VPNStr.trafficBesideTunnel, """
                \(language.rawValue): the one outcome this check exists to \
                catch is not written down
                """)
            XCTAssertEqual(drawn.mark, .warning)
            // …and it is not the same sentence as the two it must never be
            // read as.
            XCTAssertNotEqual(drawn.verdict,
                              strip(tunnel(since: stamped, exit: .unknown)).verdict)
            XCTAssertNotEqual(drawn.verdict,
                              strip(tunnel(since: stamped,
                                           exit: .throughTunnel(countryCode: nil))).verdict)
        }
    }

    /// A probe that failed is not the bad news, and never wears its mark.
    func testAnUncheckedExitIsNeitherVerdict() {
        inLanguage(.en) {
            let drawn = strip(tunnel(since: stamped, exit: .unknown))
            XCTAssertEqual(drawn.verdict, VPNStr.trafficUnknown)
            XCTAssertEqual(drawn.mark, .neutral)
        }
    }

    /// The country decorates; it is never invented. A code `Locale` cannot name
    /// falls back to the sentence without a place rather than to a dangling
    /// dash.
    func testACountryThatDoesNotResolveLeavesTheSentenceWhole() {
        inLanguage(.en) {
            XCTAssertEqual(strip(tunnel(since: stamped,
                                        exit: .throughTunnel(countryCode: "XX"))).verdict,
                           VPNStr.trafficThroughTunnel)
            XCTAssertEqual(strip(tunnel(since: stamped,
                                        exit: .throughTunnel(countryCode: "NL"))).verdict,
                           VPNStr.trafficThroughTunnel(country: VPNStr.country("NL") ?? ""))
        }
    }

    // MARK: - 6. While it runs

    func testWhileMeasuringTheButtonIsGoneAndTheWordIsThere() {
        inEachLanguage { language in
            let drawn = strip(tunnel(since: stamped), measuring: true)
            XCTAssertEqual(drawn.action, .running(VPNStr.measuring), """
                \(language.rawValue): the button is still offered while a run \
                is in flight, so a second press starts a second fifteen seconds
                """)
        }
        // On the screen: the control is gone and a spinner stands in its place.
        let quiet = mount(tunnel(since: stamped))
        XCTAssertEqual(quiet.host.everyView(named: "_FocusRingView").count, 1,
                       "precondition: the probe cannot see the button it is looking for")
        XCTAssertTrue(quiet.host.everyView(ofType: NSProgressIndicator.self).isEmpty,
                      "precondition: something is already spinning with no run in flight")

        let running = mount(tunnel(since: stamped), measuring: true)
        XCTAssertTrue(running.host.everyView(named: "_FocusRingView").isEmpty,
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
        vm.measureSpeed()
        XCTAssertTrue(vm.measuring, "precondition: the press never started a run")

        // What the engine writes when the tool answered nothing: the state it
        // already had, with `speed` still nil.
        let payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: "incy", status: .connected, kind: "IKEv2")],
            autoConnected: [], defaultName: "incy", lastAutomation: nil,
            facts: tunnel(since: stamped))
        transport.emit(EngineEvent(name: VPNEvent.state.rawValue,
                                   payload: try! JSONEncoder().encode(payload)))
        for _ in 0..<80 where vm.facts == nil {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(vm.facts, "the wire did not deliver: the reading below would be of nothing")
        XCTAssertNil(vm.facts?.speed, "precondition: this is the run that answered nothing")
        XCTAssertFalse(vm.measuring, """
            a refused run left the spinner turning: nothing about the state \
            changed, so a rule that watches the figure never fires
            """)
    }
}
