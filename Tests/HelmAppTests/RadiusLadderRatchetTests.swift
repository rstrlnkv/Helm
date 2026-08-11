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
/// decision, it is what the audit counts on the mockup side, and it is stable:
/// three consecutive runs agreed on the seven below to the value.
///
/// The cost is stated plainly: a mutation that reuses a radius already in the
/// set — a second 12 pt card — is invisible to this test. It catches a radius
/// that is *new*, which is what drift is.
///
/// **A ratchet, not a gate.** Seven is what the tree drew on the day this
/// landed, and it is only ever lowered by the commit that lowers it.
@MainActor
final class RadiusLadderRatchetTests: XCTestCase {

    /// Measured 2026-08-11 against `main` = `8b8c547`:
    /// 1, 1.25, 2, 3, 5, 8 and **12**. The last is `HelmSurface.cardRadius`, the
    /// one v3 moves to 10, and it is the single value drawn most often. 5 is
    /// SwiftUI's own pop-up bezel and 1 and 1.25 are hairlines and dividers —
    /// they are in the count deliberately, because deciding a hairline is not a
    /// corner is a decision somebody should take in the open rather than a rule
    /// hidden in a test.
    private static let recorded = 7

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
