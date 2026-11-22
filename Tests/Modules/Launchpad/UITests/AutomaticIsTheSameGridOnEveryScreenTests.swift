import AppKit
import XCTest
import HelmUI
@testable import Module_Launchpad_UI

/// Automatic is seven columns and five rows on every screen, and only the size of what is drawn follows the screen; the multiplier makes the icon smaller or larger
/// than the automatic one on the common screens. Each failure prints the size and the result.
final class AutomaticIsTheSameGridOnEveryScreenTests: XCTestCase {
    /// Width, height and the top the menu bar and the notch keep.
    private let screens: [(w: CGFloat, h: CGFloat, top: CGFloat)] = [
        (1024, 768, 24), (1280, 800, 24), (1440, 900, 24), (1512, 982, 33), (2560, 1440, 24), (3440, 1440, 24), (1080, 1920, 24)]
    private let common: [(w: CGFloat, h: CGFloat, top: CGFloat)] = [(2560, 1440, 24), (1512, 982, 33), (1440, 900, 24), (1280, 800, 24)]

    private func make(_ screen: (w: CGFloat, h: CGFloat, top: CGFloat), multiplier: Double = 1) -> LaunchpadGeometry {
        var settings = LaunchpadGridSettings.standard
        settings.sizeMultiplier = multiplier
        return .make(for: CGSize(width: screen.w, height: screen.h), topSafe: screen.top, settings: settings)
    }

    func testEveryScreenIsSevenByFiveAndPagesTheSameList() {
        for screen in screens {
            let g = make(screen)
            XCTAssertEqual(g.columns, 7, "\(screen): \(g.columns)x\(g.rows) icon \(g.icon)")
            XCTAssertEqual(g.rows, 5, "\(screen): \(g.columns)x\(g.rows) icon \(g.icon)")
            XCTAssertEqual(g.capacity, 35, "\(screen)")
            XCTAssertGreaterThanOrEqual(g.icon, LaunchpadMetrics.iconFloor, "\(screen): icon \(g.icon)")
            XCTAssertLessThanOrEqual(g.icon, LaunchpadMetrics.automaticIconCeiling, "\(screen): icon \(g.icon)")
        }
    }

    func testTheIconGrowsWithTheScreen() {
        let order = [screens[0], screens[1], screens[2], screens[3], screens[4]]
        let icons = order.map { make($0).icon }
        XCTAssertEqual(icons, icons.sorted(), "1024x768, 1280x800, 1440x900, 1512x982, 2560x1440: \(icons)")
    }

    func testAScreenThatIsNotOneStillMakesAFiniteGrid() {
        for size in [CGSize.zero, CGSize(width: CGFloat.nan, height: CGFloat.nan), CGSize(width: CGFloat.infinity, height: CGFloat.infinity), CGSize(width: -5, height: 10), CGSize(width: 1e9, height: 1e9)] {
            for top in [CGFloat.nan, -1, .infinity, 1e9] {
                let g = LaunchpadGeometry.make(for: size, topSafe: top)
                XCTAssertTrue(LaunchpadMetrics.scaleRange.contains(g.scale), "\(size) top \(top): scale \(g.scale)")
                XCTAssertTrue(g.icon.isFinite && g.cellWidth.isFinite && g.cellHeight.isFinite, "\(size) top \(top): icon \(g.icon) cell \(g.cellWidth)x\(g.cellHeight)")
                XCTAssertGreaterThanOrEqual(g.icon, LaunchpadMetrics.iconFloor, "\(size) top \(top)")
            }
        }
    }

    func testTheMultiplierMakesTheIconSmallerAndLargerOnTheCommonScreens() {
        for screen in common {
            let small = make(screen, multiplier: 0.8).icon, same = make(screen).icon, large = make(screen, multiplier: 1.25).icon
            XCTAssertLessThan(small, same, "\(screen): x0.8 \(small), x1 \(same)")
            XCTAssertGreaterThan(large, same, "\(screen): x1 \(same), x1.25 \(large)")
            XCTAssertLessThanOrEqual(large, LaunchpadMetrics.automaticIconCeiling, "\(screen): x1.25 \(large)")
        }
    }

    /// Printed for the page: what the owner sees at each end.
    func testPrintTheTable() {
        print("screen (top) | multiplier | scale | icon | cell w x h | label pt")
        for screen in common {
            for m in [0.8, 1, 1.25] {
                let g = make(screen, multiplier: m)
                let label = HelmText.rowDetailNSFont.pointSize * max(1, g.scale)
                print(String(format: "%.0fx%.0f (%.0f) | x%.2f | s %.3f | icon %.0f | %.1f x %.1f | %.2f pt", screen.w, screen.h, screen.top, m, g.scale, g.icon, g.cellWidth, g.cellHeight, label))
            }
        }
    }

    /// "Festplattendienstprogramm" has no space or hyphen: the tile gives it one line (`LaunchpadTile`: `lineLimit(1)`, `minimumScaleFactor(unbreakableShrink)`, `allowsTightening`), then cuts it
    /// with an ellipsis. What is printed is its width at the label's size, at the shrunk size, and the room the cell leaves; it is asserted not cut on the screens listed.
    func testTheGermanLabelIsNotCutOnTheScreensListed() {
        let shrink = LaunchpadMetrics.unbreakableShrink
        for screen in screens {
            let name = "\(Int(screen.w))x\(Int(screen.h))"
            for m in [0.8, 1, 1.25] {
                let g = make(screen, multiplier: m)
                let size = HelmText.rowDetailNSFont.pointSize * max(1, g.scale)
                let wide = ("Festplattendienstprogramm" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width
                let room = g.cellWidth - 2 * g.tilePadding
                print(String(format: "German label, %@ x%.2f: s %.3f, font %.2f pt, text %.1f pt (%.1f at %.2f), room %.1f pt -> %@", name, m, g.scale, size, wide, wide * shrink, shrink, room, wide <= room ? "whole" : wide * shrink <= room ? "shrunk" : "cut"))
                XCTAssertLessThanOrEqual(wide * shrink, room, "\(name) x\(m): cut")
            }
        }
    }

    /// The header row's top: the notch's room or the menu bar's, the taller (`LaunchpadWindow.topSafe`).
    @MainActor func testTheTopRoomIsTheTallerOfTheNotchAndTheMenuBar() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(LaunchpadWindow.topSafe(safeTop: 32, frame: frame, visible: CGRect(x: 0, y: 0, width: 1512, height: 949)), 33, "notched: the bar is 33, the notch 32")
        XCTAssertEqual(LaunchpadWindow.topSafe(safeTop: 0, frame: frame, visible: CGRect(x: 0, y: 0, width: 1512, height: 958)), 24, "external screen with a bar")
        XCTAssertEqual(LaunchpadWindow.topSafe(safeTop: 0, frame: frame, visible: frame), 0, "bar hidden, no notch")
    }

    /// The tabs begin at the left edge of the grid shown: the category view's 6 columns start further in than the 7 of the grid.
    func testTheTabsBeginWhereTheGridShownBegins() {
        for screen in screens {
            let g = make(screen), paired = g.pairedColumns
            XCTAssertEqual(g.sideInset, g.gridLeft, accuracy: 0.001, "\(screen)")
            XCTAssertEqual(paired.sideInset, paired.gridLeft, accuracy: 0.001, "\(screen): categories")
            XCTAssertEqual(paired.columns, 6, "\(screen)")
        }
    }
}
