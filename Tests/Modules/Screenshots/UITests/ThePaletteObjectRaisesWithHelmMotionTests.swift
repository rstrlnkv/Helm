import HelmTestSupport
import XCTest

/// **The chosen object travels on HelmMotion's curve, gated by HelmMotion's own `travels`.** What `travels` answers is
/// asserted by value in `ThePaletteObjectRaisesOnlyWithMotionTests` (HelmUITests), and the 10 pt it stands higher by
/// pixels in `ThePaletteObjectStandsTenPointsHigherTests`; the part no value shows is that the view *asks*: the
/// animation is `HelmMotion.interface` behind `HelmMotion.travels(reduceMotion:)`, read from the live setting, and no
/// curve is spelled in the file. That is what this reads, with the shadows (two native ones, the artwork carries none).
final class ThePaletteObjectRaisesWithHelmMotionTests: XCTestCase {
    private func code() throws -> String {
        try RepoSource.lines(of: "Sources/Modules/Screenshots/UI/PaletteObject.swift").map(RepoSource.code).joined(separator: "\n")
    }

    func testTheAnimationIsHelmMotionsAndGatedByTravels() throws {
        let joined = try code()
        XCTAssertTrue(joined.contains("HelmMotion.travels(reduceMotion: HelmMotion.reduceMotion)"),
                      "the lift does not ask HelmMotion.travels with the live setting")
        XCTAssertTrue(joined.contains("? HelmMotion.interface : nil"), "the curve is not HelmMotion.interface or none")
        XCTAssertNotNil(joined.range(of: #"\.animation\(\s*travel\s*,\s*value:\s*raised\s*\)"#, options: .regularExpression),
                        "the travel is not what animates the raised flag")
    }

    func testNoCurveIsSpelledOutsideHelmMotion() throws {
        let joined = try code()
        for curve in [".spring(", ".easeInOut(", ".easeOut(", ".easeIn(", ".linear(", ".bouncy", ".smooth", ".snappy", ".interpolatingSpring("] {
            XCTAssertFalse(joined.contains(curve), "a curve spelled outside HelmMotion: \(curve)")
        }
    }

    func testTwoNativeShadowsAndNoWithAnimationOfItsOwn() throws {
        let joined = try code()
        XCTAssertEqual(joined.components(separatedBy: ".shadow(").count - 1, 2, "two native shadows")
        XCTAssertFalse(joined.contains("withAnimation"), "a transaction of its own")
    }
}
