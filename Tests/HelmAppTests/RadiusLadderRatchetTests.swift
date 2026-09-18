import AppKit
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A corner has one ladder: 4 · 6 · 10 · 14 · 26 pt.**
///
/// The mockup audit counted sixteen distinct radii against three declared
/// tokens (`v3/audit.js`, check `space-off-the-ladder`). Radius is the one
/// ladder that survives the render — SwiftUI leaves it on `CALayer.cornerRadius`
/// — so this one is measured on the nine drawn pages rather than on the source,
/// and it therefore catches a radius nobody typed: a shape clipped by an
/// ancestor, a value arrived at by arithmetic. `14.56` was in the first reading
/// and is in no source file.
///
/// **The count is of distinct values, not of layers.** Every other ladder here
/// counts occurrences; this one cannot. How many layers carry a radius is a fact
/// about how many rows a list happens to draw, and that moves with content and
/// with the machine — 12 pt appeared on 118 layers in one reading and 41 in
/// another with nothing changed but a scroll view's realization. A *value* is a
/// decision, it is what the audit counts on the mockup side, and it is nearly
/// stable: three consecutive runs agree on the values below except for Disk's
/// 1.25, which comes and goes with the scan the person last ran — `recorded`
/// says what that turned out to be, and `ModulePageRender.floors` carries the
/// measurement.
///
/// The cost is stated plainly: a mutation that reuses a radius already in the
/// set — a second 12 pt card — is invisible to this test. It catches a radius
/// that is *new*, which is what drift is.
///
/// **A ratchet, not a gate.** Seven is what the tree drew on the day this
/// landed, and it is only ever lowered by the commit that lowers it.
@MainActor
final class RadiusLadderRatchetTests: XCTestCase {

    /// Re-measured 2026-08-11 with the v3 tokens in: 1, 1.25, 2, 3, 5 and
    /// **12**, three runs before the change and three after giving 6, 6, 5 both
    /// times. 5 is SwiftUI's own pop-up bezel and 1 and 1.25 are hairlines and
    /// dividers — they are in the count deliberately, because deciding a hairline
    /// is not a corner is a decision somebody should take in the open rather than
    /// a rule hidden in a test. The 1.25 is Disk's, and it is the run-to-run
    /// wobble: that page redraws the person's own last scan, so the ceiling of
    /// the same reading is 6 and its floor is 5.
    ///
    /// **The 12 is not the card's, and the 8 in the first reading is gone.** Both
    /// were written down here as facts about Helm's own drawing and neither was.
    /// Probed layer by layer: every 12 pt layer is a `_NSGraphicsView` or a
    /// `PlatformGroupContainer` 704 pt wide — which is `HelmLayout.cardWidth`,
    /// SwiftUI's own grouped-`Form` section card — plus one search field bezel.
    /// Helm's own card radius was 12 too and was hiding behind it: moving it to
    /// `HelmRadius.card` = 10 took sixteen layers off 12 across three pages and
    /// left the distinct value exactly where it was. The 8 pt now reads only off
    /// `AppKitSwitch` end caps, which `isSystemDrawn` filters, and no run
    /// reproduces it anywhere else.
    ///
    /// **Read that sixteen with the paragraph below in hand.** Setting
    /// `HelmRadius.card` to 11 drew no 11 pt layer anywhere when this was written,
    /// and 12 pt still read off the same three pages — so whatever those sixteen
    /// layers were, they were not `.helmCard()`. That half of the claim expired on
    /// 2026-08-12: `card` = 11 now draws on seven pages, and the paragraph below
    /// carries the reading. Nobody has re-derived the sixteen.
    ///
    /// **And 6 is a ceiling over a wobble, which costs resolution.** The reading
    /// is 6 when Disk draws a tree and 5 when it does not. The wobble is *not*
    /// the mounted volumes this comment first blamed — those arrive through
    /// `DiskCommand.volumes`, which no fixture answers and none should, so the
    /// picker is empty on every Mac. It is the person's own last scan, read off
    /// `~/Library/Application Support/Helm/Disk/last-scan.json` because
    /// `DiskViewModel.shared(vm:)` takes no store, and 1.25 is a 6 pt corner
    /// clamped by a bar 2.5 pt wide — arithmetic on the byte distribution of
    /// somebody's disk. Measured: 172 layers at 17:59:50 and 50 at 17:59:59, one
    /// commit, nine seconds apart, with 1.25 only in the first.
    /// `TheSuiteDoesNotReadTheUsersLastScanTests` holds the seam that ends it.
    ///
    /// **6 goes to 5 in the commit that lands that seam, and not before.** With
    /// the seam in place the reading was 5 in six consecutive runs — and with it
    /// missing, recording 5 is a red CI for the day after every Disk scan,
    /// wearing a message about corner radii. So the number here still carries one
    /// slot of slack, deliberately, and the guard that removes it is red until
    /// somebody does.
    ///
    /// **What that costs was measured, and both halves of the measurement have
    /// since expired. Read the next paragraph, not this one.** It said:
    /// `HelmRadius.card` = 11 pt passes this test and no 11 pt layer is drawn,
    /// because none of that token's five call sites is on screen at first launch —
    /// Disk's volume cards, VPN's connection cards, Autopilot's history and rule
    /// editor and `HelmBanner` all needing a reply the transport never gave. And:
    /// a mutation this test *does* catch is `HelmChoiceCards`' 6 pt `clipShape` →
    /// 19 pt, drawn on VPN's page. **That probe has since gone too — see the
    /// paragraph after next.**
    ///
    /// **Both re-measured 2026-08-12 and neither holds.** `HelmRadius.card` = 11
    /// now draws `11.00 pt on autopilot, disk, duplicates, layout, leftovers,
    /// uninstaller, vpn` and takes this count to 8 — six of those seven pages need
    /// no fixture at all, so the token reached the first-launch screens somewhere
    /// between that reading and the tree-wide vocabulary sweep, and the reach
    /// problem this paragraph described is smaller than it was. The choice-cards
    /// mutation went the other way: `HelmChoiceCards` is drawn on exactly one
    /// module page, VPN's notice section, which `5b675ad` put behind
    /// `!connections.isEmpty` — so from that commit until the wire fixture landed
    /// a 19 pt corner on it was caught by **nothing**, measured both ways on
    /// 2026-08-12 (unwired: five green; wired: `19.00 pt on vpn`, 8 and 7).
    ///
    /// **And that probe is dead as of 2026-08-17: do not reach for it.** VPN's
    /// notice section left the page — the picture question is asked inside a
    /// *popover* on each connection card now, and a popover is a window macOS
    /// orders in, so `ModulePageRender` never draws one. `HelmChoiceCards` kept
    /// its last call site in `AppearancePicker`, which only the app's General
    /// page draws, and the corner itself moved out of both into
    /// `View.helmPreviewEdge`. Measured rather than reasoned: that modifier's
    /// `HelmRadius.ctl` → 19 pt, both the clip and the overlay, leaves all five
    /// tests here green. Whoever needs a live probe for this file has to find a
    /// component the nine module pages actually draw and record the reading —
    /// mutating this one and reading green proves nothing at all.
    ///
    /// **A live probe existed for one day, it did not fire, and it has since left
    /// the tree — measured 2026-08-18, gone the same day.** The component the
    /// paragraph above asks for was VPN's tunnel strip: it drew four
    /// `HelmRadius.ctl` wells in the render, and unlike a
    /// `.background(RoundedRectangle)` that never reaches a layer, those did —
    /// probed layer by layer, `19.00 pt on vpn`, four layers, with the strip's
    /// own well radius mutated. **The ratchet stayed green anyway.** The wells
    /// were then removed by the strip's redesign — the four columns are
    /// separated by whitespace now and draw no fill at all — so there is again
    /// no live probe here, and mutating the strip proves nothing. The reason the
    /// mutant was absorbed is a free slot rather than a blind spot: the tree
    /// draws **7 distinct off-ladder radii in light and 6 in dark, three
    /// consecutive runs**, against the 8 and 7 recorded below. The `2.00` in the
    /// last reading left with the notices section when it became a popover, and
    /// the slot it vacated is what the mutant was absorbed by.
    ///
    /// So the pair below is a ceiling one above the floor, and a first new radius
    /// anywhere is free. Lowering it to 7 and 6 is what would make this probe bite
    /// — and it is deliberately **not** done here, because the paragraph on Disk's
    /// 1.25 says in bold what that costs: the wobble that slot was reserved for
    /// comes and goes with the person's own last scan, and recording the tight
    /// number before `TheSuiteDoesNotReadTheUsersLastScanTests`' seam lands is a
    /// red CI on the day after every Disk scan, wearing a message about corners.
    /// The measurement is written down so that decision is taken by whoever lands
    /// the seam, with the reading in hand, rather than re-derived.
    ///
    /// A claim about what a check cannot see is itself a measurement, and it goes
    /// stale in whichever direction the tree moves. Both of these were true when
    /// written.
    ///
    /// So this number goes down by one, and the reason is the 8 rather than the
    /// card. What that says about the 12 is worth reading before anybody lowers
    /// it further: while the pages are grouped `Form`s **no commit here can move
    /// it**, and a ratchet with an unreachable floor is a shape this suite has
    /// been caught by before. Either `isSystemDrawn` learns those two class names
    /// — which hides a real value in order to make a number move — or the floor
    /// is stated out loud as 1. That is a decision for the commit that rebuilds
    /// the pages, not for the one that lands the tokens.
    ///
    /// **And the 8 came back, in light mode, because this reading had a second
    /// weather nobody had named: the screen.** The render inherited
    /// `NSApp.effectiveAppearance`, this Mac switches appearance by the sun, and
    /// at 04:34:58 on 2026-08-12 the ratchet went red with nothing committed since
    /// 03:05. The value is `Slider`'s knob — a 20 × 16 pt capsule at (556.5, 473)
    /// on Keep Awake's battery-floor row, `cornerRadius` 8, owned by
    /// `PlatformGroupContainer` — and SwiftUI draws that layer **in light only**.
    /// So the number is per appearance now, six in light and five in dark,
    /// measured three consecutive runs each; `testTheTwoScreensDrawTheSameRadii`
    /// holds the difference by value, so a per-screen slot cannot quietly absorb
    /// a new radius the way a count on its own would. **That asymmetry is gone
    /// as of 2026-09-18 — the knob draws in both screens now; the paragraph at
    /// the end of this comment carries the reading, and it is the one to read.**
    /// **Re-read 2026-08-12 by the tree-wide typography and space sweep, and it
    /// does not move — which is the answer, not a failure to try.** That sweep
    /// took every corner radius Helm types onto `HelmRadius`, including the two
    /// that were off this ladder: `HelmGlyphPicker`'s 7 and `HelmDurationField`'s
    /// 8, both now `.ctl`. Three consecutive runs after it read **1, 2, 3, 5, 8,
    /// 12** in light and the same without 8 in dark — the numbers below, exactly.
    ///
    /// Two things that reading settles, both of which this comment had been
    /// carrying as claims:
    ///
    /// - **The 8 really is the slider knob.** Helm's own 8 pt corner left the
    ///   tree in this sweep and an 8 still draws, on keep-awake, in light only.
    ///   That is now a measurement rather than an attribution.
    /// - **The 1.25 did not appear in any of the three runs.** The wobble this
    ///   number carries a slot of slack for is quiet today, which is not the same
    ///   as gone: it comes and goes with the person's own last scan, and the seam
    ///   that ends it is still owed.
    ///
    /// So the floor here is unreachable by a vocabulary pass, and the reason is
    /// the one written above: every value left belongs to SwiftUI, not to Helm.
    ///
    /// **7 and 6 as of 2026-08-12, and the seventh value is a capsule.**
    /// `ModulePageRender.Wire` answers Homebrew's `status` from a fixture, so this
    /// reading covers its *manager* screen for the first time — the render had only
    /// ever drawn the «not installed» screen, 12 layers of it — and that screen
    /// draws `HelmBadge`. Probed layer by layer: **7.50 pt, on a 33 × 15 layer
    /// inside a `CellHostingView`, on homebrew, in both appearances**, three
    /// consecutive runs. `HelmBadge.quiet` is a `Capsule`, so its radius is half
    /// its own height and 15 pt of pill gives 7.5 — which is the third value in
    /// this count that no commit can lower without changing what the shape *is*,
    /// beside SwiftUI's 12 pt form card and 5 pt pop-up bezel.
    ///
    /// That is a decision this file should not take on its own: a capsule is not a
    /// corner chosen by eye, and a ratchet counting it has one more slot that can
    /// never be spent. Either `Drawn` learns to name a capsule (`radius` ≈
    /// `height / 2`) and this count excludes it the way `isSystemDrawn` excludes
    /// AppKit's, or the pair below carries it for good. Recorded honestly until
    /// somebody decides, and named here so the next reader does not re-derive it.
    /// **8 and 7 as of 2026-08-12, and the eighth value is a plate.** The
    /// Keyboard module's introduction was a `.sheet`, which is a window — five
    /// per render and nothing of it inside the page's own layers, so the first
    /// screen a new user meets was measured by nothing at all. It is the page's
    /// own first section now, and it brings `HelmIconPlate` with it: **11.44 pt
    /// on layout, in both appearances, three consecutive runs**, which is
    /// `size * 0.26` at the 44 pt plate an introduction draws.
    ///
    /// The same kind of value as the 7.5 pt capsule above and not a corner
    /// anybody chose: the plate's radius is a fixed proportion of its size, so
    /// there is no size on this ladder to move it to — 26 pt would give 6.76 and
    /// 40 pt 10.4. Lowering it means changing what the shape *is*, and the
    /// decision named for the capsule — `Drawn` learning to name a derived
    /// radius — is the same decision that would take this slot back.
    private static let recorded: [NSAppearance.Name: Int] = [.aqua: 8, .darkAqua: 7]

    private static let ladder: [CGFloat] = [0, 4, 6, 10, 14, 26]

    /// Half a point, the audit's own tolerance: a radius drawn at 9.9997 is 10.
    private static let tolerance: CGFloat = 0.6

    func testRadiiOffTheLadderDoNotGrow() {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let values = offLadder(in: appearance, checkingEachPageDrew: true)
            let report = values.sorted { $0.key < $1.key }.map { value, pages in
                "\(value) pt on \(pages.sorted().joined(separator: ", "))"
            }
            let recorded = Self.recorded[appearance] ?? 0
            XCTAssertLessThanOrEqual(values.count, recorded, """
                \(values.count) distinct corner radii are off the ladder \
                \(Self.ladder.dropFirst().map { String(Int($0)) }.joined(separator: "·")) \
                in \(screen); the recorded number for that screen is \(recorded).
                This number is only ever lowered, by the commit that lowers it.
                \(report.joined(separator: "\n"))
                """)
        }
    }

    /// **A per-screen slot is a free slot, so there is none.** A ratchet of two
    /// counts would let a genuinely new radius arrive in one screen for nothing,
    /// as long as it arrived while that screen's accounted-for extra was still
    /// there — six is six. So the difference between the two screens is pinned by
    /// value rather than by count, in both directions.
    ///
    /// **The value that difference used to hold was SwiftUI's slider knob, and it
    /// is not a difference any more — measured 2026-09-18 on macOS 27.2
    /// (`26B5086k`).** The knob still draws: a 20 × 16 pt capsule of
    /// `cornerRadius` 8 at (556.5, 445) on Keep Awake's battery-floor row, owned
    /// by `PlatformGroupContainer`. What changed is that SwiftUI now draws that
    /// layer in **dark as well** — identical frame, identical radius, three
    /// consecutive runs agreeing to the byte, both screens reading the same six
    /// values (1, 3, 5, 7.5, 8, 12).
    ///
    /// **Probed rather than reasoned, because "the knob stopped drawing" and "dark
    /// started drawing it" fail this check identically.** Narrowing the slider's
    /// own `.frame(width:)` from 160 to 100 moved that 8 pt layer from x = 556.5
    /// to x = 596.5 **in both screens** — which is where the knob of a 5…50 slider
    /// seeded at 20 % lands on each width. So the layer is the knob, the row still
    /// draws it, and nothing on Keep Awake's page regressed.
    ///
    /// This is a tightening and not a lowering: the slot the 8 occupied was
    /// spent, and now there is no slot at all in either direction. The 8 itself is
    /// still not Helm's and still not lowerable here — `isSystemDrawn` cannot see
    /// it, because that layer has no view of its own to be named after, only the
    /// `PlatformGroupContainer` it hangs under, and teaching the filter that class
    /// name would hide `PanelBars`' and `HelmChoiceCards`' layers with it. It is
    /// simply counted on both screens now instead of one, which is what
    /// `recorded` above carries.
    ///
    /// **And this file finally has a live probe again — measured 2026-09-18.**
    /// Making `HelmBadge`'s background shape appearance-conditional at 2.75 pt in
    /// light and 3.25 pt in dark turns this check red in both directions at once:
    /// `light draws ["2.75"]` and `dark draws ["3.25"]`. So the assertion below is
    /// a guard that has been seen to fail, on the defect it is for.
    ///
    /// **What the first two attempts at that probe cost is worth more than the
    /// probe: a background shape's radius is clamped on the way to the layer.**
    /// The same mutation at 17 and 18 pt read back as **7.50 on every badge, in
    /// both screens** — unchanged from the capsule it replaced — because these
    /// pills are 15 pt tall and the radius that reaches `CALayer.cornerRadius` is
    /// capped at half the smaller side. That is why so many mutations recorded in
    /// this comment were «absorbed»: a probe that reaches for a big obvious number
    /// on a small view is invisible to a reading taken off the layer, and reads
    /// exactly like a check that cannot see anything. Probe **below** half the
    /// view's shorter side, or the green is about the clamp and not about the
    /// check. (`HelmBadge.quiet` alone is also not enough — these pages draw both
    /// variants, and the first attempt changed only one.)
    ///
    /// **What this costs, stated the way the rest of this file states it.** The
    /// check now says the two screens draw the *same* set, so it goes red on any
    /// radius that is appearance-conditional in either direction — including the
    /// knob going back to light-only, which is what an older macOS would draw.
    /// That is the reading being recorded, not a property of SwiftUI anybody
    /// promised: whoever sees this red on a different macOS should re-take the
    /// measurement above before changing the expectation, because a check that
    /// accepts both shapes would have passed on the day this one caught the move.
    func testTheTwoScreensDrawTheSameRadii() {
        let light = Set(offLadder(in: .aqua, checkingEachPageDrew: false).keys)
        let dark = Set(offLadder(in: .darkAqua, checkingEachPageDrew: false).keys)

        XCTAssertFalse(light.isEmpty, "nothing was measured in either screen")
        XCTAssertEqual(light.subtracting(dark), [], """
            light draws \(light.subtracting(dark).sorted()) where dark does not. The one value \
            that was ever accounted for here is 8.00 pt — SwiftUI's slider knob on Keep Awake's \
            battery row — and on 2026-09-18, macOS 27.2, it draws in both screens, so this \
            difference is empty. Re-take the reading before recording anything else.
            """)
        XCTAssertEqual(dark.subtracting(light), [], """
            dark draws \(dark.subtracting(light).sorted()) where light does not, which is a \
            radius no reading of this tree has seen before.
            """)
    }

    /// The off-ladder radii of one screen, each with the pages that drew it.
    private func offLadder(in appearance: NSAppearance.Name,
                           checkingEachPageDrew: Bool) -> [String: Set<String>] {
        var values: [String: Set<String>] = [:]
        for page in ModulePageRender.pages(in: appearance) {
            if checkingEachPageDrew { page.assertItDrewSomething() }
            for layer in page.layers where isOffLadder(layer) {
                values[String(format: "%.2f", layer.radius), default: []].insert(page.id)
            }
        }
        return values
    }

    private func isOffLadder(_ layer: ModulePageRender.Drawn) -> Bool {
        guard !layer.isSystemDrawn, layer.radius > 0.01, layer.radius.isFinite else { return false }
        return !Self.ladder.contains { abs($0 - layer.radius) < Self.tolerance }
    }

    // MARK: - The measurement itself

    /// The render reaches every module, and every module draws. Without this the
    /// test above passes on a process with no window server, where nine empty
    /// bitmaps have no radii at all and the ratchet reads zero.
    ///
    /// In both screens, because a page that draws nothing in one of them is a page
    /// half the people using the app cannot see.
    func testEveryModulePageDrawsSomethingToMeasure() {
        for appearance in RenderedInk.bothAppearances {
            let pages = ModulePageRender.pages(in: appearance)
            XCTAssertEqual(pages.map(\.id).sorted(),
                           ModuleRegistry.all.map(\.idRaw).sorted(),
                           "the render is not covering the registry")
            for page in pages { page.assertItDrewSomething() }
            XCTAssertGreaterThan(pages.flatMap(\.layers).filter { $0.radius > 0.01 }.count, 100,
                                 "no page drew a rounded corner at all in "
                                 + "\(RenderedInk.label(of: appearance)) — the reading is not radii")
        }
    }

    /// The ladder is doing work: most of what is drawn *is* on it, so the values
    /// above read as exceptions rather than as an arbitrary slice.
    ///
    /// Light, which is the screen that draws the superset: whatever this says of
    /// light it says of dark, plus the knob.
    func testMostDrawnRadiiAreOnTheLadder() {
        let drawn = ModulePageRender.pages(in: .aqua).flatMap(\.layers)
            .filter { !$0.isSystemDrawn && $0.radius > 0.01 && $0.radius.isFinite }
        let off = drawn.filter(isOffLadder)
        XCTAssertFalse(drawn.isEmpty)
        XCTAssertLessThan(Double(off.count) / Double(drawn.count), 0.9,
                          "\(off.count) of \(drawn.count) drawn radii are off the ladder — "
                          + "either the ladder is wrong or the reading is")
    }

    /// The rule recognises the shape it was written for, and lets a step
    /// through. A fixture rather than the tree, so it goes on saying this once
    /// the tree is fixed — the Swift twin of the `probe` every check in
    /// `v3/audit.js` carries.
    func testTheRuleRecognisesARadiusChosenByEye() {
        let byEye = ModulePageRender.Drawn(frame: .zero, radius: 15, hasContents: false,
                                           owner: "PlatformGroupContainer")
        let onLadder = ModulePageRender.Drawn(frame: .zero, radius: 10, hasContents: false,
                                              owner: "PlatformGroupContainer")
        let macOS = ModulePageRender.Drawn(frame: .zero, radius: 6.5, hasContents: false,
                                           owner: "_NSCoreHostingView<AppKitSwitch>")
        XCTAssertTrue(isOffLadder(byEye), "15 pt is on no step and must be reported")
        XCTAssertFalse(isOffLadder(onLadder), "10 pt is a step")
        XCTAssertFalse(isOffLadder(macOS),
                       "a switch's end cap is macOS drawing its own control, "
                       + "and no commit here can lower it")
    }
}
