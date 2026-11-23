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

    /// "Festplattendienstprogramm" with no break point (the built German name has soft hyphens and breaks, below; read from Disk Utility's built `InfoPlist.loctable` (de) with `plutil -convert xml1`, 2026-11-22): the tile gives it one line shrunk to `unbreakableShrink`, and where that is still wider than the
    /// room (the cell is square now, so the room is the cell less the side padding: 130.2 pt at 1512 x 982) it is cut, and the hover scrolls it. Every figure is `LaunchpadLabel`'s, the table and the tile read one
    /// function. Asserted: the distance is finite and not negative, and reaches the end of the line clear of the fade.
    func testTheMarqueeCanReachTheWholeGermanNameOnTheScreensListed() {
        for name in ["Festplattendienstprogramm", "Festplatten\u{AD}dienstprogramm"] {
            for screen in screens {
                let label = "\(Int(screen.w))x\(Int(screen.h))"
                for m in [0.8, 1, 1.25] {
                    let g = make(screen, multiplier: m)
                    let size = LaunchpadLabel.fontSize(scale: g.scale) * LaunchpadLabel.shrink(name)
                    let line = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width
                    let room = LaunchpadLabel.room(width: g.cellWidth, scale: g.scale)
                    let distance = LaunchpadLabel.overflow(name: name, room: room, scale: g.scale, oneLine: false)
                    print(String(format: "German label %@, %@ x%.2f: s %.3f, shown at %.2f pt, line %.1f pt, room %.1f pt -> %@, scroll %.1f pt", name.contains("\u{AD}") ? "soft-hyphened" : "unbroken",
                                 label, m, g.scale, size, line, room, distance > 0 ? "cut" : "whole", distance))
                    XCTAssertTrue(distance.isFinite && distance >= 0, "\(label) x\(m)")
                    if distance > 0 { XCTAssertEqual(room + distance, line + LaunchpadLabel.fade, accuracy: 0.001, "\(label) x\(m): the end stops where the fade begins") }
                }
            }
        }
    }

    /// The pitch is square on every screen and multiplier: a column is as wide as a row is high, the grid is narrower than the usable width, the large mark is `p + icon`, and the grid begins where
    /// the tabs do.
    func testTheCellIsSquareOnEveryScreenAndTheGridFitsItsWidth() {
        for screen in screens {
            for m in [0.8, 1, 1.25] {
                let g = make(screen, multiplier: m), tag = "\(screen) x\(m)"
                XCTAssertEqual(g.cellWidth, g.cellHeight, accuracy: 0.0001, tag)
                XCTAssertEqual(g.largeMark, g.cellHeight + g.icon, accuracy: 0.0001, tag)
                XCTAssertLessThanOrEqual(CGFloat(g.columns) * g.cellWidth, screen.w * (1 - 2 * LaunchpadMetrics.sideMargin) + 0.001, tag)
                XCTAssertEqual(g.sideInset, g.gridLeft, accuracy: 0.001, tag)
                XCTAssertEqual(g.pairedColumns.cellWidth, g.pairedColumns.cellHeight, accuracy: 0.0001, tag)
            }
        }
    }

    /// A multiplier above 1 never makes the icon smaller than ×1 gives, on a screen where the seven columns, not the five rows, are what runs out first (tall and narrow): the scale
    /// is held where seven cells stop fitting the width, as it is held where five rows stop fitting the height.
    func testAMultiplierAboveOneNeverShrinksTheIconOnATallNarrowScreen() {
        var held = 0
        for width in stride(from: CGFloat(500), through: 1600, by: 50) {
            let one = make((width, 4000, 0)), up = make((width, 4000, 0), multiplier: 1.25)
            let tag = "\(width) wide"
            XCTAssertGreaterThanOrEqual(up.icon, one.icon - 0.0001, tag)
            XCTAssertEqual(up.columns, one.columns, tag)
            if up.scale < one.scale * 1.25 - 0.001 { held += 1 }
        }
        XCTAssertGreaterThan(held, 0, "subject: some of these widths hold the scale below what the multiplier asked")
    }

    /// A narrow screen shrinks the icon and keeps seven columns; a column goes only where seven cells at the floor icon do not fit the usable width (the icon then grows again, to fill the fewer columns).
    func testANarrowScreenShrinksTheIconBeforeItDropsAColumn() {
        var last = CGFloat.infinity
        for width in stride(from: CGFloat(1400), through: 300, by: -50) {
            let g = LaunchpadGeometry.make(for: CGSize(width: width, height: 1600), topSafe: 0)
            let floorRow = 7 * LaunchpadMetrics.cellHeight(icon: LaunchpadMetrics.iconFloor, names: true, scale: g.scale)
            XCTAssertEqual(g.columns < 7, floorRow > width * (1 - 2 * LaunchpadMetrics.sideMargin), "\(width): seven columns at the floor icon take \(floorRow), the grid has \(g.columns)")
            if g.columns == 7 {
                XCTAssertLessThanOrEqual(g.icon, last, "\(width): the icon only shrinks as the screen narrows")
                last = g.icon
            }
            XCTAssertEqual(g.cellWidth, g.cellHeight, accuracy: 0.0001)
        }
        XCTAssertEqual(LaunchpadGeometry.make(for: CGSize(width: 700, height: 1600), topSafe: 0).columns, 7, "the control: 700 pt still holds seven")
        XCTAssertLessThan(LaunchpadGeometry.make(for: CGSize(width: 350, height: 1600), topSafe: 0).columns, 7, "the control: 350 pt does not")
    }

    /// The 2 x 2 well of a large folder, a category block or the Hidden block lines up with the visible bodies of the four small icons it stands for (an icon's body is `wellShare` of its frame,
    /// centred): the block's cells are `2p` wide, its mark `p + icon`, centred, and its well begins a small icon's inset in. Printed at 1512 x 982.
    func testALargeWellCoversTheVisibleBodiesOfTheFourIconsItStandsFor() {
        for screen in screens {
            for m in [0.8, 1, 1.25] {
                let g = make(screen, multiplier: m), tag = "\(screen) x\(m)"
                let body = g.icon * LaunchpadMetrics.wellShare, p = g.cellWidth
                // Cells (0,0) and (1,1) of the block's place: each small icon's visible body.
                let first = CGRect(x: (p - g.icon) / 2 + (g.icon - body) / 2, y: g.iconTop + (g.icon - body) / 2, width: body, height: body)
                let last = first.offsetBy(dx: p, dy: p)
                // The mark, centred in the block's 2p width, and the well in it.
                let well = LaunchpadFolderMark.well(g.largeMark, edge: g.largeEdge)
                let origin = CGPoint(x: (2 * p - g.largeMark) / 2 + g.largeEdge, y: g.iconTop + g.largeEdge)
                XCTAssertEqual(origin.x, first.minX, accuracy: 0.0001, tag); XCTAssertEqual(origin.y, first.minY, accuracy: 0.0001, tag)
                XCTAssertEqual(origin.x + well, last.maxX, accuracy: 0.0001, tag); XCTAssertEqual(origin.y + well, last.maxY, accuracy: 0.0001, tag)
                XCTAssertEqual(well, p + body, accuracy: 0.0001, tag)
                if screen.w == 1512, m == 1 {
                    print(String(format: "1512x982: icon %.2f, pitch %.2f, largeMark %.2f, well %.2f from x %.2f to %.2f (icons' bodies %.2f to %.2f)", g.icon, p, g.largeMark, well, origin.x, origin.x + well, first.minX, last.maxX))
                }
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
