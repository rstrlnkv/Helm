import XCTest
@testable import Module_Layout_Engine

/// The table shipped with Sweden drawn as Ukraine — two layouts, one badge —
/// and nothing failed, because the old model could not tell the difference
/// between them. These are the tests that would have caught it.
final class FlagArtTests: XCTestCase {

    // MARK: - The bug that shipped

    func testSwedenIsNotUkraine() {
        XCTAssertNotEqual(FlagArt.flag(region: "SE"), FlagArt.flag(region: "UA"))
    }

    func testSwedenIsACross() {
        guard case .nordic = FlagArt.flag(region: "SE") else {
            return XCTFail("Sweden's flag is a cross, not two bands")
        }
    }

    // MARK: - The rule the badge exists to serve

    /// Every drawn flag must differ from every other drawn flag. An indicator
    /// that cannot tell two of a user’s layouts apart is worse than no indicator:
    /// it answers the question wrongly instead of not answering it.
    func testNoTwoRegionsDrawTheSameFlag() {
        var seen: [FlagArt: String] = [:]
        for region in FlagArt.drawnRegions {
            guard let art = FlagArt.flag(region: region) else {
                return XCTFail("\(region) is listed as drawn but has no flag")
            }
            if let other = seen[art] {
                XCTFail("\(region) and \(other) draw the same badge")
            }
            seen[art] = region
        }
    }

    // MARK: - The regions kept out, and why

    func testFlagsNeedingACrestOrCantonAreNotDrawn() {
        for region in ["US", "GB", "BR", "PT", "GR", "KR", "CN", "TR", "IL"] {
            XCTAssertNil(FlagArt.flag(region: region),
                         "\(region) cannot be drawn honestly at badge size")
        }
    }

    func testFlagsThatWouldCollideAreNotDrawn() {
        // Each of these is a true flag Helm could draw, and each is another
        // country's flag once the crest is gone.
        for region in ["MX", "SK", "SI", "HR", "RS"] {
            XCTAssertNil(FlagArt.flag(region: region),
                         "\(region) would be indistinguishable from a flag already drawn")
        }
    }

    func testUnknownAndMissingRegions() {
        XCTAssertNil(FlagArt.flag(region: nil))
        XCTAssertNil(FlagArt.flag(region: "ZZ"))
        XCTAssertNil(FlagArt.flag(region: ""))
    }

    func testRegionIsCaseInsensitive() {
        XCTAssertEqual(FlagArt.flag(region: "ru"), FlagArt.flag(region: "RU"))
    }

    // MARK: - Shape of the data

    func testProportionsAreCarried() {
        guard case let .bands(_, weights, _) = FlagArt.flag(region: "ES") else {
            return XCTFail("Spain is bands")
        }
        // Drawn as equal thirds, Spain's yellow band is half the width it
        // should be. The weights are the whole reason the case has them.
        XCTAssertEqual(weights, [1, 2, 1])
    }

    func testEveryBandHasAWeightAndEveryWeightIsPositive() {
        for region in FlagArt.drawnRegions {
            guard case let .bands(colors, weights, _) = FlagArt.flag(region: region) else { continue }
            XCTAssertEqual(colors.count, weights.count, "\(region)")
            XCTAssertFalse(colors.isEmpty, "\(region)")
            XCTAssertTrue(weights.allSatisfy { $0 > 0 }, "\(region)")
        }
    }

    func testEveryColourIsSixHexDigits() {
        let hex = CharacterSet(charactersIn: "0123456789ABCDEF")
        for region in FlagArt.drawnRegions {
            guard let art = FlagArt.flag(region: region) else { continue }
            for colour in art.colours {
                XCTAssertEqual(colour.count, 6, "\(region): \(colour)")
                XCTAssertTrue(CharacterSet(charactersIn: colour).isSubset(of: hex),
                              "\(region): \(colour)")
            }
        }
    }

    func testEveryDrawnRegionIsInTheTableAndViceVersa() {
        // The list feeds the settings preview, so a region in one and not the
        // other means the preview lies about what the menu bar will show.
        for region in FlagArt.drawnRegions {
            XCTAssertNotNil(FlagArt.flag(region: region), region)
        }
        XCTAssertEqual(Set(FlagArt.drawnRegions).count, FlagArt.drawnRegions.count)
    }
}

private extension FlagArt {
    var colours: [String] {
        switch self {
        case let .bands(colors, _, _): return colors
        case let .nordic(field, cross, border): return [field, cross] + (border.map { [$0] } ?? [])
        case let .swissCross(field, cross): return [field, cross]
        case let .disc(field, disc): return [field, disc]
        case let .hoistTriangle(top, bottom, triangle): return [top, bottom, triangle]
        }
    }
}
