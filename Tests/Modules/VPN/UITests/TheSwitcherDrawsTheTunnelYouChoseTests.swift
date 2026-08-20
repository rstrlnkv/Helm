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
/// One tunnel is **no pill where a button stands beside it** — a capsule that
/// selects between one thing, drawn in the same box as the control next to it —
/// and a pill where none does, because the row would otherwise be empty and the
/// tunnel unnamed.
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

    // MARK: - 1. A lone segment, and where it goes

    /// **A pill that selects between one thing, beside a button that does
    /// something.**
    ///
    /// This was tried the other way and reverted, and the reasoning is worth
    /// keeping: hidden below two tunnels, the row «was invisible to everybody
    /// who had never had two up at once, so the switching was reported as
    /// missing rather than as unnecessary». What answers it is that the tunnel
    /// is named anyway — card one's note is «home · utun7», 40 pt below — so
    /// dropping the pill costs the name nothing and saves a capsule that reads
    /// as pressable and is not a choice.
    ///
    /// **And it goes only where a button stands beside it.** The three actions
    /// are not the same row: `.offer` and `.running` each leave a control there,
    /// and `.notOffered` leaves nothing at all — measured, dropping the lone
    /// pill in that state takes the block from 52 pt to 22 and leaves 26 pt of
    /// `s6 + s4` standing over a floating sentence. It is also the state where
    /// the tunnel most needs naming: the traffic is not in it and its dot is
    /// grey.
    func testALoneSegmentGoesWhereAButtonStandsBesideIt() {
        let one = VPNTunnelSwitcher([tunnel("home", interface: "utun7", routed: true)],
                                    selected: nil)
        XCTAssertEqual(one.segments.map(\.name), ["home"],
                       "precondition: the switcher does not know about the tunnel at all")

        XCTAssertTrue(one.drawn(beside: .offer(VPNStr.measureSpeed)).isEmpty, """
            a Mac with one tunnel draws a selection of one beside the Measure \
            button — two capsules on one row, one of which does something
            """)
        XCTAssertTrue(one.drawn(beside: .running(VPNStr.measuring)).isEmpty, """
            the lone pill is still drawn while the measurement runs, so the row \
            it stands in is a spinner and a segment nobody can choose against
            """)
        XCTAssertEqual(one.drawn(beside: .notOffered(VPNStr.speedIsTheRoutedTunnels))
            .map(\.name), ["home"], """
            the lone pill was dropped from the one state that has no button, \
            which empties the row and leaves its spacing over a bare sentence
            """)
    }

    /// A real choice is drawn in every state, because it is one.
    func testTwoTunnelsKeepTheirSegmentsWhateverTheButtonSays() {
        let switcher = VPNTunnelSwitcher(two, selected: nil)
        for action in [VPNTunnelStrip.Action.offer(VPNStr.measureSpeed),
                       .running(VPNStr.measuring),
                       .notOffered(VPNStr.speedIsTheRoutedTunnels)] {
            XCTAssertEqual(switcher.drawn(beside: action).map(\.name), ["home", "work"],
                           "a Mac with two tunnels up lost its switching under \(action)")
        }
    }

    /// Nothing up is still nothing to switch between: the hero draws its empty
    /// state instead, and a row of no segments would be a strip of air above it.
    func testNoTunnelsDrawNoSegments() {
        XCTAssertTrue(VPNTunnelSwitcher([], selected: nil).segments.isEmpty)
    }

    /// **A selection of one is not a selection, and the fill says otherwise.**
    ///
    /// Measured off the render: the lone accent pill was a 24 pt box at the same
    /// left edge with the same corner as «Measure speed» 93 pt below it — two
    /// identical rectangles, one of which does something. The accent is a
    /// *selection* mark and carries no information when there is nothing to
    /// select against, so it is spent entirely on looking pressable. It also
    /// carried the row's one contrast failure: `HelmSignal.success` on the
    /// accent measures 1.11:1 in light against this house's 3:1 floor for a mark.
    func testASingleSegmentIsNotDrawnAsAChoice() {
        let one = VPNTunnelSwitcher([tunnel("home", interface: "utun7", routed: true)],
                                    selected: nil).segments
        XCTAssertEqual(one.count, 1, "precondition: the single segment is drawn at all")
        XCTAssertFalse(one[0].isOneOfSeveral, """
            the only tunnel there is was marked as one of several, so the row             draws an accent fill for a choice nobody has
            """)
        XCTAssertTrue(one[0].isSelected, "the only segment there is was not the chosen one")

        let two = VPNTunnelSwitcher(self.two, selected: nil).segments
        XCTAssertEqual(two.map(\.isOneOfSeveral), [true, true], """
            a real choice stopped being drawn as one, which is the case the fill             exists for
            """)
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
        AppLanguage.each { language in
            let drawn = VPNTunnelStrip(tunnel("work", interface: "utun4"), now: now)
            XCTAssertEqual(drawn.action, .notOffered(VPNStr.speedIsTheRoutedTunnels), """
                \(language.rawValue): a tunnel that is not carrying the traffic \
                offers a measurement that would be taken on a different link
                """)
        }
    }

    func testTheRoutedTunnelStillOffersTheButton() {
        AppLanguage.each { language in
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
        XCTAssertEqual(tile?.note,
                       VPNStr.speedNote(HelmDates.relative(taken, to: now, style: .short)))
    }

    /// And a tunnel that is not carrying the traffic quotes no price at all,
    /// because there is no press to pay it.
    ///
    /// The button's price tag used to be quoted in this column and is gone
    /// altogether, so this asks the thing that decides:
    /// the column says the unit, and the action is the sentence rather than an
    /// offer. Asserted together, because «the note is the unit» is true of the
    /// routed tunnel too and would be a check that cannot fail on its own.
    func testANonRoutedTunnelOffersNoPressAndQuotesNoPrice() {
        AppLanguage.each { language in
            let drawn = VPNTunnelStrip(tunnel("work", interface: "utun4"), now: now)
            let tile = drawn.tiles.first { $0.kind == .speed }
            XCTAssertEqual(tile?.value, VPNTunnelStrip.noReading,
                           "precondition: \(language.rawValue) drew a figure from nowhere")
            XCTAssertEqual(tile?.note, VPNStr.speedUnit,
                           "\(language.rawValue): the column says something other than the unit")
            XCTAssertEqual(drawn.action, .notOffered(VPNStr.speedIsTheRoutedTunnels), """
                \(language.rawValue): a tunnel that is not carrying the traffic is \
                offered a measurement, which would be taken on another tunnel and \
                drawn under this one's name
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
            VPNTunnelHero(tunnels, selected: .constant(selected), now: now,
                          measuring: nil, measure: { _ in })
                .padding(HelmSpace.s5)
        }
        let render = MountedRender(page, width: 720, height: 260, appearance: .darkAqua)
        renders.append(render)
        render.settle(30)
        return render
    }

    /// One control with one tunnel — the Measure button, with no pill beside it
    /// — and three with two. A count, because a render is what can answer «is it
    /// there at all»; which segment says what is read off the value above.
    func testEveryTunnelIsOnTheScreenAsAControl() {
        let one = mount([tunnel("home", interface: "utun7", routed: true)])
        XCTAssertEqual(one.host.everyView(named: "_FocusRingView").count, 1, """
            a single tunnel draws \
            \(one.host.everyView(named: "_FocusRingView").count) control(s) where \
            the Measure button alone is one — a selection of one is drawn beside it
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
