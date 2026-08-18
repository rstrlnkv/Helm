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

    /// How many **wells** the drawing holds: the widest count, over every row,
    /// of runs at least 80 pt across that depart from the pane.
    ///
    /// A well is one continuous fill from edge to edge — the type inside it
    /// cannot break the run, since type departs from the pane too — while a
    /// line of words is a scatter of runs a few points wide each. 80 pt is well
    /// under the narrowest tile this strip can draw (three across 696 pt is
    /// 225 each, four is 165) and well over any glyph cluster, so the row that
    /// scores highest is a row of tiles.
    private func wells(_ render: MountedRender) -> Int {
        let view = render.host
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8
        else { return -1 }
        let scale = max(1, rep.pixelsHigh / max(1, Int(view.bounds.height)))
        let wide = 80 * scale
        var best = 0
        for y in 0..<rep.pixelsHigh {
            let row = y * rep.bytesPerRow
            // The pane's own colour on this row, read at the very edge — the
            // section is padded, so x = 0 is never inside a tile.
            let pane = (0..<3).map { Int(data[row + $0]) }
            var runs = 0, run = 0
            for x in 0..<rep.pixelsWide {
                let at = row + x * 4
                let far = (0..<3).map { abs(Int(data[at + $0]) - pane[$0]) }.max() ?? 0
                if far > 2 {
                    run += 1
                } else {
                    if run >= wide { runs += 1 }
                    run = 0
                }
            }
            if run >= wide { runs += 1 }
            best = max(best, runs)
        }
        return best
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
        // And on the screen: three wells where a stamped tunnel draws four.
        let seen = wells(mount(tunnel(since: stamped)))
        XCTAssertEqual(seen, 4, "precondition: the probe cannot see the tiles it is counting")
        XCTAssertEqual(wells(mount(tunnel(since: nil))), 3, """
            the drawing still holds four wells with no moment to report: the \
            uptime tile is being drawn empty rather than left out
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
            XCTAssertEqual(tile.note, VPNStr.speedNotYet, """
                \(language.rawValue): the tile does not say what a measurement \
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
            XCTAssertEqual(tile.note, VPNStr.speedMeasured(HelmDates.relative(taken, to: now)), """
                \(language.rawValue): a figure three minutes old is drawn \
                without its age, which reads as the link's speed now
                """)
            XCTAssertEqual(drawn.action, .offer(VPNStr.measureAgain),
                           "\(language.rawValue): the button still offers a first measurement")
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
            XCTAssertNil(tile?.note, """
                \(language.rawValue): a five-second-old reading carries an age \
                line — «\(tile?.note ?? "")»
                """)
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
