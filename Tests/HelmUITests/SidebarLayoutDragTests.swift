import XCTest
@testable import HelmUI

/// The arithmetic behind a drag, kept out of the table that draws it.
///
/// `NSTableView` speaks in flat row indices and knows nothing about sections;
/// `SidebarLayout` speaks in sections and knows nothing about rows. This is the
/// only translation between the two, and it is here rather than in the view so
/// that a drop landing in the wrong section is a failing test rather than a
/// thing somebody notices later.
final class SidebarLayoutDragTests: XCTestCase {

    /// Two sections: «a» holding disk and vpn, «b» holding brew.
    ///
    /// Flat rows:  0 header a · 1 disk · 2 vpn · 3 header b · 4 brew
    private var sample: SidebarLayout {
        SidebarLayout(sections: [
            .init(id: "a", seed: nil, name: "A", modules: ["disk", "vpn"]),
            .init(id: "b", seed: nil, name: "B", modules: ["brew"]),
        ])
    }

    // MARK: - The projection

    func testFlatteningInterleavesHeadersAndModules() {
        XCTAssertEqual(sample.flattened, [
            .section("a"), .module("disk", in: "a"), .module("vpn", in: "a"),
            .section("b"), .module("brew", in: "b"),
        ])
    }

    /// An empty section is one row, not zero. It has to be there or there is
    /// nothing to drop the first module onto.
    func testAnEmptySectionStillHasItsHeader() {
        let layout = SidebarLayout(sections: [.init(id: "a", seed: nil, name: "A", modules: [])])
        XCTAssertEqual(layout.flattened, [.section("a")])
    }

    // MARK: - Dragging a module

    /// The drop indicator sits *above* row 4, which is «brew» — so the module
    /// lands in «b», before it.
    func testAModuleDropsIntoAnotherSectionBeforeARow() {
        let after = sample.applyingDrag(of: .module("disk", in: "a"), toFlatIndex: 4)
        XCTAssertEqual(after.sections.map(\.modules), [["vpn"], ["disk", "brew"]])
    }

    /// Directly under a header: first in that section, not last.
    func testAModuleDropsFirstWhenItLandsUnderAHeader() {
        let after = sample.applyingDrag(of: .module("brew", in: "b"), toFlatIndex: 1)
        XCTAssertEqual(after.sections.map(\.modules), [["brew", "disk", "vpn"], []])
    }

    /// Past the last row: the end of the last section.
    func testAModuleDropsLastAtTheVeryEnd() {
        let after = sample.applyingDrag(of: .module("disk", in: "a"), toFlatIndex: 5)
        XCTAssertEqual(after.sections.map(\.modules), [["vpn"], ["brew", "disk"]])
    }

    /// Row 0 is above the first header, where no section exists. The drop is
    /// clamped into the first section rather than refused: refusing a drop the
    /// indicator was already drawn for is the table lying about where it would
    /// land.
    func testAModuleDroppedAboveTheFirstHeaderClampsIntoIt() {
        let after = sample.applyingDrag(of: .module("brew", in: "b"), toFlatIndex: 0)
        XCTAssertEqual(after.sections.map(\.modules), [["brew", "disk", "vpn"], []])
    }

    /// A drag that ends where it began. The layout comes back identical, and in
    /// particular the module is not removed and re-appended.
    func testAModuleDroppedOnItsOwnPlaceChangesNothing() {
        XCTAssertEqual(sample.applyingDrag(of: .module("vpn", in: "a"), toFlatIndex: 2), sample)
    }

    /// Reordering inside one section is the same call and the same arithmetic.
    func testAModuleReordersWithinItsSection() {
        let after = sample.applyingDrag(of: .module("vpn", in: "a"), toFlatIndex: 1)
        XCTAssertEqual(after.sections.map(\.modules), [["vpn", "disk"], ["brew"]])
    }

    // MARK: - Dragging a section

    /// A header carries its modules. Leaving them behind would put them under a
    /// heading that no longer describes them, and the person dragged the group.
    func testASectionCarriesItsModules() {
        let after = sample.applyingDrag(of: .section("b"), toFlatIndex: 0)
        XCTAssertEqual(after.sections.map(\.id), ["b", "a"])
        XCTAssertEqual(after.sections.map(\.modules), [["brew"], ["disk", "vpn"]])
    }

    /// Dropped among another section's modules, a section lands before that
    /// section rather than splitting it.
    func testASectionDroppedInsideAnotherLandsBeforeIt() {
        let after = sample.applyingDrag(of: .section("b"), toFlatIndex: 2)
        XCTAssertEqual(after.sections.map(\.id), ["b", "a"])
    }

    func testASectionDropsLastAtTheVeryEnd() {
        let after = sample.applyingDrag(of: .section("a"), toFlatIndex: 5)
        XCTAssertEqual(after.sections.map(\.id), ["b", "a"])
    }

    /// Whatever the drop, every module is still present exactly once. The
    /// invariant the whole type exists for does not get a holiday during a drag.
    func testNoDropEverLosesOrDuplicatesAModule() {
        let rows = sample.flattened
        for row in rows {
            for target in 0...rows.count {
                let after = sample.applyingDrag(of: row, toFlatIndex: target)
                let placed = after.sections.flatMap(\.modules)
                XCTAssertEqual(placed.sorted(), ["brew", "disk", "vpn"],
                               "dropping \(row) at \(target) lost or duplicated a module")
                XCTAssertEqual(after.sections.count, 2,
                               "dropping \(row) at \(target) lost a section")
            }
        }
    }
}
