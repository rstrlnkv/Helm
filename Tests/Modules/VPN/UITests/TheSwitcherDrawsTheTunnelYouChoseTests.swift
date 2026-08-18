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

/// **With two tunnels up the second was drawn nowhere.**
///
/// The strip is about one tunnel and always was; what it lacked was a way to say
/// *which*. The tunnels that are up are a row of segments above the columns now,
/// and three rules hold it together.
///
/// One tunnel is **no switcher at all** — a control offering one choice is noise
/// on a card that is already four columns and a sentence.
///
/// The selection is a name and the list is rewritten under it whenever the
/// network moves, so a tunnel that drops leaves the page holding a word that
/// names nothing. It falls back to the first — which is the routed one, by
/// `VPNTunnelChoice.primaryFirst` — rather than emptying a card with two other
/// tunnels to draw.
///
/// And the speed button exists only on the tunnel carrying the default route.
/// `networkQuality` cannot be bound to an interface here, so an unbound run
/// follows the route whatever the switcher is showing; on the others the column
/// keeps its label and its figure, and the sentence says why there is nothing to
/// press.
///
/// Asserted on the values, for the reason `TheStripDrawsOnlyWhatIsKnownTests`
/// records: an `NSHostingView`'s accessibility tree is empty under this suite
/// and SwiftUI draws its own text, so the strings are read off
/// `VPNTunnelSwitcher` and `VPNTunnelStrip` — with the render asked only what a
/// render can answer, which is whether the controls are there at all.
@MainActor
final class TheSwitcherDrawsTheTunnelYouChoseTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var stamped: Date { now.addingTimeInterval(-(3600 + 14 * 60)) }

    private func tunnel(_ name: String, interface: String,
                        bytesIn: UInt64? = 1_200_000_000,
                        bytesOut: UInt64? = 210_000_000,
                        routed: Bool = false,
                        speed: VPNSpeedReading? = nil,
                        measuring: Bool = false) -> VPNTunnelState {
        VPNTunnelState(name: name, interface: interface, since: stamped,
                       bytesIn: bytesIn, bytesOut: bytesOut,
                       exit: routed ? .throughTunnel(countryCode: "NL") : .besideTunnel,
                       speed: speed, measuring: measuring)
    }

    private var two: [VPNTunnelState] {
        [tunnel("home", interface: "utun7", routed: true),
         tunnel("work", interface: "utun4", bytesIn: 33_000_000, bytesOut: 7_000_000)]
    }

    private func inEachLanguage(_ body: (AppLanguage) -> Void) {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            body(language)
        }
    }

    // MARK: - 1. One tunnel is no switcher

    func testOneTunnelDrawsNoSwitcherAtAll() {
        let one = [tunnel("home", interface: "utun7", routed: true)]
        XCTAssertTrue(VPNTunnelSwitcher(one, selected: nil).segments.isEmpty, """
            a switcher was drawn over a single tunnel — a control offering one \
            choice, on a card that already names that tunnel under its first column
            """)
        XCTAssertTrue(VPNTunnelSwitcher([], selected: nil).segments.isEmpty)
    }

    func testTwoTunnelsEachGetASegmentInTheOrderTheyCame() {
        let segments = VPNTunnelSwitcher(two, selected: nil).segments
        XCTAssertEqual(segments.map(\.name), ["home", "work"], """
            the segments do not match the list the engine sent, so «the first» — \
            which is what a lost selection falls back to — names something else here
            """)
    }

    // MARK: - 2. Which segment is on

    func testTheSegmentThePersonPickedIsTheSelectedOne() {
        let segments = VPNTunnelSwitcher(two, selected: "work").segments
        XCTAssertEqual(segments.filter(\.isSelected).map(\.name), ["work"])
    }

    func testWithNoSelectionAtAllTheFirstSegmentIsOn() {
        let segments = VPNTunnelSwitcher(two, selected: nil).segments
        XCTAssertEqual(segments.filter(\.isSelected).map(\.name), ["home"], """
            a page opened with nothing picked draws a row where no segment is on, \
            over a strip that is drawing one of them
            """)
    }

    /// **The rule this file is named for.** The selection is a state of one
    /// visit, held against a list the engine rewrites; a tunnel that dropped —
    /// or that Helm was told to disconnect — leaves the word behind.
    func testASelectionWhoseTunnelHasGoneFallsBackToTheFirst() {
        let left = [tunnel("home", interface: "utun7", routed: true),
                    tunnel("cafe", interface: "utun9")]
        let switcher = VPNTunnelSwitcher(left, selected: "work")

        XCTAssertEqual(switcher.chosen?.name, "home", """
            the strip is empty while two tunnels are up: the selection still names \
            «work», which has gone, and nothing put it back on the first
            """)
        XCTAssertEqual(switcher.segments.filter(\.isSelected).map(\.name), ["home"], """
            the strip fell back and the row did not, so the card draws one tunnel \
            with a different one lit above it
            """)
    }

    /// Every tunnel in the row is up by construction — the engine lists only
    /// connected ones — so a dot meaning «connected» would be the same mark on
    /// every segment. What varies is which one the traffic leaves through, and
    /// that is also what decides whether the card below has a button.
    func testOnlyTheTunnelCarryingTheTrafficIsMarked() {
        let segments = VPNTunnelSwitcher(two, selected: "work").segments
        XCTAssertEqual(segments.filter(\.carriesTraffic).map(\.name), ["home"])
    }

    /// Two tunnels up and the route on Wi-Fi is an ordinary Mac: nothing is
    /// marked, and nothing is invented.
    func testWithTheRouteOnNeitherTunnelNoSegmentIsMarked() {
        let neither = [tunnel("home", interface: "utun7"), tunnel("work", interface: "utun4")]
        XCTAssertTrue(VPNTunnelSwitcher(neither, selected: nil).segments
            .allSatisfy { !$0.carriesTraffic })
    }

    // MARK: - 3. The card follows the switcher

    func testSelectingTheSecondDrawsTheSecondsFigures() {
        let chosen = VPNTunnelSwitcher(two, selected: "work").chosen
        let drawn = VPNTunnelStrip(chosen ?? two[0], now: now)

        XCTAssertEqual(drawn.tiles.first { $0.kind == .uptime }?.note,
                       VPNStr.tunnelAndInterface("work", "utun4"), """
            the card still names the tunnel it opened on after the person picked \
            the other one
            """)
        XCTAssertTrue(drawn.tiles.first { $0.kind == .down }?.value.contains("33") == true,
                      "the figures under the second segment are the first tunnel's")
    }

    // MARK: - 4. The offer belongs to the routed tunnel

    /// A measurement is unbound and follows the default route, so offering one
    /// here would file «home»'s figure under «work»'s name.
    func testANonRoutedTunnelSaysWhyThereIsNoButton() {
        inEachLanguage { language in
            let drawn = VPNTunnelStrip(tunnel("work", interface: "utun4"), now: now)
            XCTAssertEqual(drawn.action, .notOffered(VPNStr.speedIsTheRoutedTunnels), """
                \(language.rawValue): a tunnel that is not carrying the traffic \
                offers a measurement that would be taken on a different link
                """)
        }
    }

    func testTheRoutedTunnelStillOffersTheButton() {
        inEachLanguage { language in
            let drawn = VPNTunnelStrip(tunnel("home", interface: "utun7", routed: true), now: now)
            XCTAssertEqual(drawn.action, .offer(VPNStr.measureSpeed),
                           "\(language.rawValue): the tunnel the traffic goes through cannot "
                           + "be measured at all")
        }
    }

    /// A routing reading that could not be made is not permission to attribute a
    /// measurement — the same direction `VPNExitVerdict.unknown` is refused in
    /// the engine.
    func testAnUncheckedTunnelIsNotOfferedOneEither() {
        let unchecked = VPNTunnelState(name: "home", interface: "utun7", since: stamped,
                                       bytesIn: nil, bytesOut: nil, exit: .unknown, speed: nil)
        XCTAssertEqual(VPNTunnelStrip(unchecked, now: now).action,
                       .notOffered(VPNStr.speedIsTheRoutedTunnels))
    }

    /// **The figure is kept.** It was taken while that tunnel held the route, so
    /// it is that tunnel's own reading, and it carries its age the moment it is
    /// too old to stand as the link's speed now.
    func testANonRoutedTunnelKeepsTheFigureItWasMeasuredWith() {
        let taken = now.addingTimeInterval(-180)
        let reading = VPNSpeedReading(down: 212, up: 95, rpm: 340, at: taken)
        let drawn = VPNTunnelStrip(tunnel("work", interface: "utun4", speed: reading), now: now)
        let tile = drawn.tiles.first { $0.kind == .speed }

        XCTAssertEqual(tile?.label, VPNStr.tileSpeed, "precondition: no speed column at all")
        XCTAssertTrue(tile?.value.contains("212") == true, """
            the tunnel's own measurement was dropped because the route moved off it
            """)
        XCTAssertEqual(tile?.note, VPNStr.speedNote(HelmDates.relative(taken, to: now)))
    }

    /// And with no figure it does not advertise the price of a press there is no
    /// button to make: `speedNotYet` is that button's price tag.
    func testANonRoutedTunnelWithNoFigureDoesNotQuoteAPriceNobodyCanPay() {
        inEachLanguage { language in
            let tile = VPNTunnelStrip(tunnel("work", interface: "utun4"), now: now)
                .tiles.first { $0.kind == .speed }
            XCTAssertEqual(tile?.value, VPNTunnelStrip.noReading,
                           "precondition: \(language.rawValue) drew a figure from nowhere")
            XCTAssertEqual(tile?.note, VPNStr.speedUnit, """
                \(language.rawValue): the column quotes «\(VPNStr.speedNotYet)» under a \
                tunnel whose card has a sentence where the button would be
                """)
        }
    }

    /// A run in flight still wins over both, because it is the state that is
    /// actually happening.
    func testARunInFlightIsSaidWhateverElseIsTrue() {
        let drawn = VPNTunnelStrip(tunnel("home", interface: "utun7", routed: true),
                                   now: now, measuring: true)
        XCTAssertEqual(drawn.action, .running(VPNStr.measuring))
    }

    // MARK: - 5. On the screen

    private func mount(_ tunnels: [VPNTunnelState], selected: String? = nil) -> MountedRender {
        let page = ZStack {
            Color(nsColor: .windowBackgroundColor)
            VPNTunnelSection(tunnels, selected: .constant(selected), now: now,
                             measuring: nil, measure: { _ in })
                .padding(HelmSpace.s5)
        }
        let render = MountedRender(page, width: 720, height: 260, appearance: .darkAqua)
        renders.append(render)
        render.settle(30)
        return render
    }

    /// One control on the card with one tunnel — the Measure button — and three
    /// with two, which is that button and a segment each. A count, because a
    /// render is what can answer «is it there at all»; which segment says what
    /// is read off the value above.
    func testTheSwitcherIsAbsentAtOneTunnelAndDrawnAtTwo() {
        let one = mount([tunnel("home", interface: "utun7", routed: true)])
        XCTAssertEqual(one.host.everyView(named: "_FocusRingView").count, 1, """
            a switcher is on the screen over a single tunnel, or the probe cannot \
            see the button it is counting
            """)

        let both = mount(two)
        XCTAssertEqual(both.host.everyView(named: "_FocusRingView").count, 3, """
            two tunnels are up and the card draws \
            \(both.host.everyView(named: "_FocusRingView").count) control(s): one \
            segment each and the Measure button is three
            """)
    }

    /// And on a non-routed tunnel the button is gone while the segments stay —
    /// so the sentence is not merely present in the value, it is what the card
    /// actually draws.
    func testTheButtonIsGoneOnATunnelThatIsNotCarryingTheTraffic() {
        let render = mount(two, selected: "work")
        XCTAssertEqual(render.host.everyView(named: "_FocusRingView").count, 2, """
            the Measure button is still on the screen for a tunnel the run would \
            not be measuring
            """)
    }
}
