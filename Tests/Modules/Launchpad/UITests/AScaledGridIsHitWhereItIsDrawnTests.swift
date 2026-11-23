import AppKit
import SwiftUI
import XCTest
import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Pass 22: the grid's sizes follow the screen, and the pointer's reading (`LaunchpadHit`) and the drawing (`LaunchpadTile`) must still agree. Each failure prints
/// the screen, the multiplier and the cell it is about. Sizes the owner meets: 2560 x 1440 at x1.25 (the largest icon), 1280 x 800 at x0.8 (the smallest).
@MainActor final class AScaledGridIsHitWhereItIsDrawnTests: XCTestCase {
    private typealias Screen = (name: String, size: CGSize, top: CGFloat, multiplier: Double)
    private let screens: [Screen] = [
        ("2560x1440 x1.25", CGSize(width: 2560, height: 1440), 24, 1.25), ("1280x800 x0.8", CGSize(width: 1280, height: 800), 24, 0.8),
        ("1512x982 notch x1", CGSize(width: 1512, height: 982), 33, 1), ("3440x1440 x1.25", CGSize(width: 3440, height: 1440), 24, 1.25),
        ("1024x768 x1.25", CGSize(width: 1024, height: 768), 24, 1.25), ("1080x1920 x1", CGSize(width: 1080, height: 1920), 24, 1)]

    private func make(_ screen: Screen, names: Bool = true) -> LaunchpadGeometry {
        var settings = LaunchpadGridSettings.standard
        settings.sizeMultiplier = screen.multiplier
        settings.showNames = names
        return .make(for: screen.size, topSafe: screen.top, settings: settings)
    }

    // MARK: Drawn where it is hit

    /// A tile is drawn on its own and the icon's red is looked for: the icon's box must be the one the hit reads (`g.iconTop`, `g.icon`, centred in the cell).
    private func redBox(of view: some View, width: CGFloat, height: CGFloat) throws -> CGRect? {
        let m = MountedRender(view.frame(width: width, height: height), width: width, height: height, appearance: .darkAqua)
        m.settle()
        let rep = try XCTUnwrap(m.host.bitmapImageRepForCachingDisplay(in: m.host.bounds))
        m.host.cacheDisplay(in: m.host.bounds, to: rep)
        let k = CGFloat(rep.pixelsWide) / width
        var box: CGRect?
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.redComponent > 0.8, c.greenComponent < 0.4, c.blueComponent < 0.35, c.alphaComponent > 0.9 else { continue }
                let pixel = CGRect(x: CGFloat(x) / k, y: CGFloat(y) / k, width: 1 / k, height: 1 / k)
                box = box.map { $0.union(pixel) } ?? pixel
            }
        }
        return box
    }

    private func red(_ side: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill(); image.unlockFocus()
        return image
    }

    private func tile(_ g: LaunchpadGeometry, size: CGFloat, image: NSImage) -> some View {
        LaunchpadTile(app: CatalogApp(id: "a", name: "Calculator", path: "/Applications/Calculator.app"), icon: image, iconSize: size, selected: false,
                      glowSize: CGSize(width: g.cellWidth, height: g.cellHeight), popped: false, open: {}, hide: {},
                      showName: g.names, scale: g.scale)
    }

    func testTheIconIsDrawnWhereTheHitReadsIt() throws {
        for screen in screens {
            for names in [true, false] {
                let g = make(screen, names: names)
                let box = try XCTUnwrap(try redBox(of: tile(g, size: g.icon, image: red(g.icon)), width: g.cellWidth, height: g.cellHeight), "\(screen.name): no icon drawn")
                XCTAssertEqual(box.minY, g.iconTop, accuracy: 1.5, "\(screen.name) names \(names): drawn top \(box.minY), hit reads \(g.iconTop) (scale \(g.scale))")
                XCTAssertEqual(box.height, g.icon, accuracy: 1.5, "\(screen.name) names \(names)")
                XCTAssertEqual(box.midX, g.cellWidth / 2, accuracy: 1.5, "\(screen.name) names \(names)")
                XCTAssertEqual(box.width, g.icon, accuracy: 1.5, "\(screen.name) names \(names)")
                XCTAssertLessThanOrEqual(g.iconTop + g.icon + g.chrome - g.iconTop, g.cellHeight + 0.001, "\(screen.name): the tile's parts fit its cell")
            }
        }
    }

    func testALargeMarkIsDrawnWhereTheBlocksIconTopReadsIt() throws {
        for screen in screens {
            let g = make(screen)
            let mark = g.largeMark
            let box = try XCTUnwrap(try redBox(of: tile(g, size: mark, image: red(mark)), width: 2 * g.cellWidth, height: 2 * g.cellHeight), "\(screen.name)")
            XCTAssertEqual(box.minY, g.iconTop, accuracy: 1.5, "\(screen.name): drawn \(box.minY), read \(g.iconTop)")
            XCTAssertEqual(box.width, mark, accuracy: 1.5, "\(screen.name)")
            XCTAssertEqual(box.midX, g.cellWidth, accuracy: 1.5, "\(screen.name)")
        }
    }

    // MARK: Hit

    private func surface(_ g: LaunchpadGeometry, count: Int) -> LaunchpadSurface {
        LaunchpadSurface(geometry: g, page: 0, pageCounts: [count], gap: nil)
    }

    func testEveryCornerOfEveryIconHitsItsOwnTile() {
        for screen in screens {
            for names in [true, false] {
                let g = make(screen, names: names)
                let s = surface(g, count: g.capacity)
                for slot in 0..<g.capacity {
                    let cell = g.frame(of: g.cell(slot)).offsetBy(dx: 0, dy: g.gridTop)
                    // Independent of `iconTop`: the tile draws its icon `s3 * scale` under its top, centred.
                    let icon = CGRect(x: cell.midX - g.icon / 2, y: cell.minY + HelmSpace.s3 * g.scale, width: g.icon, height: g.icon)
                    for p in [CGPoint(x: icon.minX + 0.01, y: icon.minY + 0.01), CGPoint(x: icon.maxX - 0.01, y: icon.minY + 0.01),
                              CGPoint(x: icon.minX + 0.01, y: icon.maxY - 0.01), CGPoint(x: icon.maxX - 0.01, y: icon.maxY - 0.01)] {
                        guard case .tile(let address, _) = LaunchpadHit.at(p, in: s) else {
                            XCTFail("\(screen.name) names \(names) slot \(slot) corner \(p): \(LaunchpadHit.at(p, in: s))"); continue
                        }
                        XCTAssertEqual(address, slot, "\(screen.name) names \(names) corner \(p)")
                    }
                    XCTAssertEqual(LaunchpadHit.at(CGPoint(x: icon.midX, y: icon.midY), in: s), .tile(address: slot, core: true), "\(screen.name) names \(names) slot \(slot): the icon's middle")
                    // The core's top and bottom are the drawn icon's (`iconTop` follows the scale): half a point inside is core, half a point outside is not.
                    XCTAssertEqual(LaunchpadHit.at(CGPoint(x: icon.midX, y: icon.minY + 0.5), in: s), .tile(address: slot, core: true), "\(screen.name) names \(names) slot \(slot): just inside the icon's top")
                    XCTAssertEqual(LaunchpadHit.at(CGPoint(x: icon.midX, y: icon.minY - 0.5), in: s), .tile(address: slot, core: false), "\(screen.name) names \(names) slot \(slot): just above the icon")
                    XCTAssertEqual(LaunchpadHit.at(CGPoint(x: icon.midX, y: icon.maxY - 0.5), in: s), .tile(address: slot, core: true), "\(screen.name) names \(names) slot \(slot): just inside the icon's bottom")
                    XCTAssertEqual(LaunchpadHit.at(CGPoint(x: icon.midX, y: icon.maxY + 0.5), in: s), .tile(address: slot, core: false), "\(screen.name) names \(names) slot \(slot): just below the icon")
                    // The cell's own corners and the label are the tile (cells touch: the gap between two is the tile's padding).
                    for p in [CGPoint(x: cell.minX + 0.01, y: cell.minY + 0.01), CGPoint(x: cell.maxX - 0.01, y: cell.maxY - 0.01)] {
                        XCTAssertEqual(LaunchpadHit.at(p, in: s), .tile(address: slot, core: false), "\(screen.name) names \(names) slot \(slot) cell corner")
                    }
                }
            }
        }
    }

    func testTheCellsAreOneAnotherAndTheSidesAboveAndBelowAreNone() {
        for screen in screens {
            let g = make(screen)
            let s = surface(g, count: g.capacity - 3)
            let left = g.gridLeft, right = g.gridLeft + CGFloat(g.columns) * g.cellWidth
            XCTAssertEqual(g.gridLeft, g.sideInset, accuracy: 0.001, "\(screen.name): the tabs start where the grid does")
            if left > LaunchpadLiftTiming.edgeWidth + 1 {
                XCTAssertEqual(LaunchpadHit.at(CGPoint(x: left - 0.5, y: g.gridTop + 5), in: s), .none, "\(screen.name): the margin left of the grid")
                XCTAssertEqual(LaunchpadHit.at(CGPoint(x: right + 0.5, y: g.gridTop + 5), in: s), .none, "\(screen.name): the margin right of the grid")
            }
            XCTAssertEqual(LaunchpadHit.at(CGPoint(x: g.size.width / 2, y: g.gridTop - 0.5), in: s), .none, "\(screen.name): above")
            XCTAssertEqual(LaunchpadHit.at(CGPoint(x: g.size.width / 2, y: g.gridTop + g.pageHeight + 0.5), in: s), .none, "\(screen.name): below")
            // A column boundary belongs to the column on its right, the pixel before it to the left one.
            let y = g.gridTop + g.iconTop + 1
            XCTAssertEqual(LaunchpadHit.at(CGPoint(x: left + g.cellWidth - 0.01, y: y), in: s), .tile(address: 0, core: false), "\(screen.name)")
            XCTAssertEqual(LaunchpadHit.at(CGPoint(x: left + g.cellWidth + 0.01, y: y), in: s), .tile(address: 1, core: false), "\(screen.name)")
            // The three empty cells at the end are the gap, not a tile.
            for n in 0..<3 {
                XCTAssertEqual(LaunchpadHit.at(g.center(ofSlot: g.capacity - 1 - n), in: s), .gap(address: g.capacity - 3), "\(screen.name) empty cell \(n)")
            }
        }
    }

    func testTheCardAnswersEveryCornerOfEveryCellAndStaysInTheWindow() {
        for screen in screens {
            let g = make(screen)
            for count in [1, g.columns, 3 * g.columns, 100] {
                var s = surface(g, count: g.capacity)
                let card = LaunchpadSurface.Card(geometry: g, count: count)
                s.card = card
                XCTAssertTrue(CGRect(origin: .zero, size: g.size).contains(card.rect), "\(screen.name) \(count) apps: card \(card.rect)")
                let shown = min(count, card.capacity)
                for slot in 0..<shown {
                    // Where `folderCard` draws the cell, worked out from the card's own padding (18 x scale), title (22) and gap (12 x scale), not from `card.origin`.
                    let c = CGPoint(x: card.rect.minX + HelmSpace.s6 * g.scale + (CGFloat(slot % card.columns) + 0.5) * g.cellWidth,
                                    y: card.rect.minY + HelmSpace.s6 * g.scale + 22 + HelmSpace.s5 * g.scale + (CGFloat(slot / card.columns) + 0.5) * g.cellHeight)
                    for (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
                        let p = CGPoint(x: c.x + dx * (g.cellWidth / 2 - 0.01), y: c.y + dy * (g.cellHeight / 2 - 0.01))
                        XCTAssertEqual(LaunchpadHit.at(p, in: s), .tile(address: slot, core: false), "\(screen.name) \(count) apps slot \(slot) corner \(p)")
                    }
                }
                XCTAssertEqual(LaunchpadHit.at(CGPoint(x: card.rect.midX, y: card.rect.minY + g.cardPadding / 2), in: s), .none, "\(screen.name): the card's padding")
                XCTAssertEqual(LaunchpadHit.at(CGPoint(x: card.rect.minX - LaunchpadLiftTiming.cardMargin - 1, y: card.rect.midY), in: s), .away, "\(screen.name)")
            }
        }
    }

    func testTheCategoryViewsBlocksAreHitAsTheyAreDrawn() {
        for screen in screens {
            for names in [true, false] {
                let g = make(screen, names: names).pairedColumns
                XCTAssertEqual(g.columns % 2, 0, "\(screen.name)")
                XCTAssertEqual(g.largeMark, make(screen).largeMark, accuracy: 0.001, "\(screen.name): the blocks keep their names, so the mark is the named grid's")
                let block = LaunchpadPlacement.Slot(column: 0, row: 0, span: 2)
                let s = LaunchpadSurface(geometry: g, page: 0, slots: [[block]], gap: nil, folders: [0])
                let frame = g.frame(of: block).offsetBy(dx: 0, dy: g.gridTop)
                for p in [CGPoint(x: frame.minX + 0.01, y: frame.minY + 0.01), CGPoint(x: frame.maxX - 0.01, y: frame.maxY - 0.01)] {
                    XCTAssertEqual(LaunchpadHit.at(p, in: s), .tile(address: 0, core: true), "\(screen.name) names \(names) block corner")
                }
                let local = g.frame(of: block)
                for index in 0..<4 {
                    let q = LaunchpadCategoryMark.frame(ofQuadrant: index, size: g.largeMark, edge: g.largeEdge)
                    let origin = CGPoint(x: local.midX - g.largeMark / 2, y: local.minY + g.iconTop)
                    let centre = CGPoint(x: origin.x + q.midX, y: origin.y + q.midY)
                    XCTAssertEqual(LaunchpadHit.categoryIcon(at: centre, block: local, mark: g.largeMark, edge: g.largeEdge, iconTop: g.iconTop, apps: 4), index, "\(screen.name) names \(names) quadrant \(index)")
                    XCTAssertNil(LaunchpadHit.categoryIcon(at: CGPoint(x: centre.x, y: origin.y - 0.5), block: local, mark: g.largeMark, edge: g.largeEdge, iconTop: g.iconTop, apps: 4),
                                 "\(screen.name): above the mark is no icon")
                }
            }
        }
    }

    // MARK: The header row and the dots against the grid

    private let sweep: [CGSize] = [CGSize(width: 640, height: 400), CGSize(width: 800, height: 600), CGSize(width: 1024, height: 600), CGSize(width: 1024, height: 768),
                                   CGSize(width: 1280, height: 720), CGSize(width: 1280, height: 800), CGSize(width: 1440, height: 900), CGSize(width: 1512, height: 982),
                                   CGSize(width: 1920, height: 1080), CGSize(width: 2560, height: 1440), CGSize(width: 3440, height: 1440), CGSize(width: 5120, height: 2880),
                                   CGSize(width: 1080, height: 1920)]

    func testTheHeaderRowClearsTheGridOnEveryScreen() {
        for size in sweep {
            for top in [CGFloat(0), 24, 33, 80] {
                for multiplier in [0.8, 1, 1.25] {
                    for names in [true, false] {
                        let g = geometry(size, top: top, multiplier: multiplier, names: names)
                        let tag = "\(size) top \(top) x\(multiplier) names \(names): scale \(g.scale), \(g.columns)x\(g.rows), icon \(g.icon)"
                        XCTAssertGreaterThanOrEqual(g.searchTop, top, tag)
                        XCTAssertGreaterThanOrEqual(g.gridTop, g.searchTop + LaunchpadMetrics.searchHeight, "the grid starts under the search field: \(tag)")
                        XCTAssertLessThanOrEqual(g.gridTop + g.pageHeight, g.size.height + 0.001, tag)
                    }
                }
            }
        }
    }

    private func geometry(_ size: CGSize, top: CGFloat, multiplier: Double, names: Bool) -> LaunchpadGeometry {
        var settings = LaunchpadGridSettings.standard
        settings.sizeMultiplier = multiplier
        settings.showNames = names
        return .make(for: size, topSafe: top, settings: settings)
    }

    /// The page dots sit `dotsBottom` above the window's bottom and are `dotHit` high (`pageDots`): the grid's last row must end above that. The room kept for them is
    /// 64 x scale, and they need 28 x scale + 24 (the touch size does not shrink below 1), which is more than that under a scale of 0.667: `dotsRoom(scale:)` holds the larger.
    func testThePageDotsTouchAreaDoesNotOverlapTheLastRowOnAnyScreen() {
        for size in sweep {
            for top in [CGFloat(0), 24, 33, 80] {
                for multiplier in [0.8, 1, 1.25] {
                    for names in [true, false] {
                        let g = geometry(size, top: top, multiplier: multiplier, names: names)
                        let dotsTop = size.height - g.dotsBottom - g.dotHit
                        XCTAssertLessThanOrEqual(g.gridTop + g.pageHeight, dotsTop + 0.001,
                                                 "\(size) top \(top) x\(multiplier) names \(names): scale \(g.scale), grid ends \(g.gridTop + g.pageHeight), the dots' touch area begins \(dotsTop)")
                    }
                }
            }
        }
    }
}
