import XCTest
@testable import Module_Launchpad_UI

/// At every size the settings allow, a tile's middle maps back to its own address, the open card is inside the window and the
/// edge strips are not on the grid.
final class LaunchpadGridSizesTests: XCTestCase {
    private func settings() -> [LaunchpadGridSettings] {
        var all: [LaunchpadGridSettings] = [.standard]
        for rows in [2, 4, 8] { for columns in [3, 7, 10] { for icon in [48.0, 128.0] {
            all.append(LaunchpadGridSettings(automatic: false, rows: rows, columns: columns, iconSize: icon))
        } } }
        return all + [128, 48].map { var s = LaunchpadGridSettings.standard; s.iconSize = $0; return s }
    }

    func testEveryCellFindsItself() {
        for screen in [CGSize(width: 1024, height: 640), CGSize(width: 1280, height: 800), CGSize(width: 2560, height: 1600)] {
            for setting in settings() {
                let g = LaunchpadGeometry.make(for: screen, topSafe: 0, settings: setting)
                let surface = LaunchpadSurface(geometry: g, page: 0, pageCounts: [g.capacity], gap: nil)
                for slot in 0..<g.capacity {
                    guard case .tile(let address, _) = LaunchpadHit.at(g.center(ofSlot: slot), in: surface) else { XCTFail("\(screen) \(setting) slot \(slot)"); continue }
                    XCTAssertEqual(address, slot, "\(screen) \(setting)")
                }
            }
        }
    }

    func testTheCardStaysInsideTheWindowAndTheEdgesAreOffTheGrid() {
        for setting in settings() {
            let g = LaunchpadGeometry.make(for: CGSize(width: 1024, height: 640), topSafe: 0, settings: setting)
            for count in [1, 5, 200] {
                let card = LaunchpadSurface.Card(geometry: g, count: count)
                XCTAssertTrue(CGRect(origin: .zero, size: g.size).contains(card.rect), "\(setting) \(count): \(card.rect)")
            }
            XCTAssertGreaterThanOrEqual(g.origin(ofSlot: 0).x, LaunchpadLiftTiming.edgeWidth)
        }
    }

    func testACardOf200AppsHasPagesAndItsDotsRowFitsTheWindowAtEverySize() {
        for screen in [CGSize(width: 1024, height: 640), CGSize(width: 1280, height: 800), CGSize(width: 2560, height: 1600)] {
            for setting in settings() {
                let g = LaunchpadGeometry.make(for: screen, topSafe: 0, settings: setting)
                let card = LaunchpadSurface.Card(geometry: g, count: 200)
                let bare = g.card(columns: card.columns, rows: card.visibleRows)
                XCTAssertTrue(card.paged, "\(screen) \(setting)")
                XCTAssertEqual(card.rect.height, bare.height + g.cardGap + LaunchpadGeometry.cardDots, accuracy: 0.001, "the dots row is in the card")
                XCTAssertTrue(CGRect(origin: .zero, size: g.size).contains(card.rect), "\(screen) \(setting): \(card.rect)")
                XCTAssertEqual(card.pageCount, (200 + card.capacity - 1) / card.capacity)
            }
        }
    }
}
