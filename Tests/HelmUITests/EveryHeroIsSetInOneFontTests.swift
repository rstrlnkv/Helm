import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest

/// **The scale's top step is one token, not a size seven files type out.**
///
/// Three modules lead their page with a 40 pt light line — Keep Awake's four
/// states, VPN's verdict and its empty slot, Layout's count — and every one of
/// them spelled `.system(size: 40, weight: .light)` where it stood.
/// `LayoutSettingsPage` wrote the promise down in prose: «the same 40 pt light
/// figure Keep Awake's hero draws, so two pages of this app do not measure
/// their own heroes differently». Nothing was under it. One of the seven moving
/// half a point, or losing `.monospacedDigit()`, would have been invisible
/// until somebody photographed two pages side by side.
///
/// So the size lives in `HelmText.heroFont` and `HelmText.heroFigureFont`, and
/// this is the test the prose was owed.
///
/// **A glyph is not type.** `WelcomeView` draws an `Image(systemName:)` at 40,
/// which states how big to draw a symbol against the font's metrics rather than
/// which step of the type scale a word is set on. `UISources.sizingType` is
/// that distinction, shared with the type ratchet rather than copied from it.
final class EveryHeroIsSetInOneFontTests: XCTestCase {

    /// The hero's step, written out rather than taken from the token — a
    /// pattern built from `HelmText`'s own value would agree with it whatever
    /// it became.
    private static let pattern = #"\bsystem\(\s*size:\s*(40)\b"#

    /// Where the token itself is declared, and the only file allowed to say it.
    private static let declaration = "Sources/HelmUI/DesignSystem/HelmSurfaces.swift"

    private func handSpelled() throws -> [UISources.Hit] {
        let files = try UISources.everyDrawnFile().filter { $0 != Self.declaration }
        return try UISources.sizingType(UISources.hits(matching: [Self.pattern], in: files))
    }

    func testNoPageSpellsTheHeroStepByHand() throws {
        let sites = try handSpelled()
        XCTAssertEqual(sites.count, 0, """
            \(sites.count) sites set type at the hero's step by hand; the step is \
            `HelmText.heroFont`, and `HelmText.heroFigureFont` where the hero is a number.
            \(UISources.summary(sites))
            """)
    }

    /// The token draws what the seven sites drew. Written out here as well,
    /// because a token compared against itself agrees with any size at all.
    func testTheTokensAreTheFaceThePagesDrew() {
        XCTAssertEqual(HelmText.heroFont, Font.system(size: 40, weight: .light))
        XCTAssertEqual(HelmText.heroFigureFont,
                       Font.system(size: 40, weight: .light).monospacedDigit())
        // And `Font` really does answer this question, rather than calling
        // every font equal to every other: the assertions above would pass on
        // any token at all if it did.
        XCTAssertNotEqual(HelmText.heroFont, HelmText.heroFigureFont)
        XCTAssertNotEqual(HelmText.heroFont, HelmText.metricFont)
    }

    /// The rule objects to the shape it was written for and lets the token and
    /// the glyph through — against a fixture, so it goes on saying this after
    /// the tree is clean.
    func testTheRuleReadsAHandSpelledStepAndNotATokenOrAGlyph() throws {
        let hits = try UISources.hits(matching: [Self.pattern], in: """
            Text("a").font(.system(size: 40, weight: .light))
            Text("b").font(HelmText.heroFont)
            Text("c").font(.system(size: 22, weight: .light))
            private static let hero = Font.system(size: 40, weight: .light)
            """).sorted { $0.line < $1.line }
        XCTAssertEqual(hits.map(\.line), [1, 4],
                       "the two hand-spelled steps are what it must see; the token and the "
                       + "size below it are what it must not")
    }

    /// And the scan is still reading the files heroes are drawn in. A pattern
    /// that has stopped matching reports no offenders for ever.
    func testTheScanStillReadsThePagesWithHeroes() throws {
        let files = try UISources.everyDrawnFile()
        for name in ["Sources/Modules/KeepAwake/UI/KeepAwakeHero.swift",
                     "Sources/Modules/VPN/UI/VPNTunnelHero.swift",
                     "Sources/Modules/Layout/UI/LayoutSettingsPage.swift"] {
            XCTAssertTrue(files.contains(name), "the scan is not reading \(name)")
        }
        // The control: the same family of patterns, one step down the scale,
        // still finds plenty. `size: 22` is spelled by hand on purpose.
        let control = try UISources.hits(matching: [#"\bsystem\(\s*size:\s*(1[0-9])\b"#],
                                         in: files)
        XCTAssertGreaterThan(control.count, 10,
                             "the size patterns matched \(control.count) sites in the whole "
                             + "app — a scan that has stopped matching passes for ever")
    }
}
