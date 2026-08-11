import AppKit
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
/// 1.25, which comes and goes with the volumes this Mac has mounted.
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
    /// wobble: that page enumerates this Mac's volumes, so the ceiling of the
    /// same reading is 6 and its floor is 5.
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
    /// **And 6 is a ceiling over a wobble, which costs resolution.** The reading
    /// is 6 when Disk draws its volumes and 5 when it does not, so a *new*
    /// off-ladder value hides inside the difference: mutating `HelmRadius.card`
    /// to 11 pt — a value on no step — passed three runs at 6, because 1.25 was
    /// absent from all three. Recording 5 instead would fail on the runs where
    /// Disk draws, which is a red CI on the weather. The fix is to stop the
    /// wobble rather than to pick between two bad numbers, and it belongs where
    /// the render decides what Disk's page is allowed to depend on.
    ///
    /// So this number goes down by one, and the reason is the 8 rather than the
    /// card. What that says about the 12 is worth reading before anybody lowers
    /// it further: while the pages are grouped `Form`s **no commit here can move
    /// it**, and a ratchet with an unreachable floor is a shape this suite has
    /// been caught by before. Either `isSystemDrawn` learns those two class names
    /// — which hides a real value in order to make a number move — or the floor
    /// is stated out loud as 1. That is a decision for the commit that rebuilds
    /// the pages, not for the one that lands the tokens.
    private static let recorded = 6

    private static let ladder: [CGFloat] = [0, 4, 6, 10, 14, 26]

    /// Half a point, the audit's own tolerance: a radius drawn at 9.9997 is 10.
    private static let tolerance: CGFloat = 0.6

    func testRadiiOffTheLadderDoNotGrow() {
        var values: [String: [String]] = [:]
        for page in ModulePageRender.pages() {
            page.assertItDrewSomething()
            for layer in page.layers where isOffLadder(layer) {
                values[String(format: "%.2f", layer.radius), default: []].append(page.id)
            }
        }

        let report = values.sorted { $0.key < $1.key }.map { value, pages in
            "\(value) pt on \(Set(pages).sorted().joined(separator: ", "))"
        }
        XCTAssertLessThanOrEqual(values.count, Self.recorded, """
            \(values.count) distinct corner radii are off the ladder \
            \(Self.ladder.dropFirst().map { String(Int($0)) }.joined(separator: "·")); \
            the recorded number is \(Self.recorded).
            This number is only ever lowered, by the commit that lowers it.
            \(report.joined(separator: "\n"))
            """)
    }

    private func isOffLadder(_ layer: ModulePageRender.Drawn) -> Bool {
        guard !layer.isSystemDrawn, layer.radius > 0.01, layer.radius.isFinite else { return false }
        return !Self.ladder.contains { abs($0 - layer.radius) < Self.tolerance }
    }

    // MARK: - The measurement itself

    /// The render reaches every module, and every module draws. Without this the
    /// test above passes on a process with no window server, where nine empty
    /// bitmaps have no radii at all and the ratchet reads zero.
    func testEveryModulePageDrawsSomethingToMeasure() {
        let pages = ModulePageRender.pages()
        XCTAssertEqual(pages.map(\.id).sorted(),
                       ModuleRegistry.all.map(\.idRaw).sorted(),
                       "the render is not covering the registry")
        for page in pages { page.assertItDrewSomething() }
        XCTAssertGreaterThan(pages.flatMap(\.layers).filter { $0.radius > 0.01 }.count, 100,
                             "no page drew a rounded corner at all — the reading is not radii")
    }

    /// The ladder is doing work: most of what is drawn *is* on it, so the seven
    /// above read as seven exceptions rather than as an arbitrary slice.
    func testMostDrawnRadiiAreOnTheLadder() {
        let drawn = ModulePageRender.pages().flatMap(\.layers)
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
