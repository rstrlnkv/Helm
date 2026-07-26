import XCTest
@testable import HelmRuntime

final class ModuleOrderTests: XCTestCase {
    private let registry = ["keep-awake", "vpn", "uninstaller", "homebrew"]

    func testNoStoredOrderKeepsRegistryOrder() {
        XCTAssertEqual(ModuleOrder.apply(saved: [], to: registry), registry)
    }

    func testStoredOrderWins() {
        XCTAssertEqual(ModuleOrder.apply(saved: ["vpn", "keep-awake"], to: registry),
                       ["vpn", "keep-awake", "uninstaller", "homebrew"])
    }

    /// A module added in a later version isn't in the stored order yet; it must
    /// still appear, after the ones the user arranged.
    func testUnknownModulesAppendInRegistryOrder() {
        XCTAssertEqual(ModuleOrder.apply(saved: ["homebrew"], to: registry),
                       ["homebrew", "keep-awake", "vpn", "uninstaller"])
    }

    /// A module removed from the app must not leave a hole behind.
    func testStaleIdsAreIgnored() {
        XCTAssertEqual(ModuleOrder.apply(saved: ["island", "vpn"], to: registry),
                       ["vpn", "keep-awake", "uninstaller", "homebrew"])
    }

    func testMoveProducesTheNewOrder() {
        XCTAssertEqual(ModuleOrder.move(registry, from: IndexSet(integer: 3), to: 0),
                       ["homebrew", "keep-awake", "vpn", "uninstaller"])
        XCTAssertEqual(ModuleOrder.move(registry, from: IndexSet(integer: 0), to: 4),
                       ["vpn", "uninstaller", "homebrew", "keep-awake"])
    }

    // MARK: - Applied to one category

    /// The sidebar groups modules by category, so it orders each group on its
    /// own. Arranging the flat list must still be respected inside a group:
    /// the user's relative order first, then anything untouched, in registry
    /// order.
    func testOrderAppliesInsideACategorySubset() {
        let saved = ["keep-awake", "vpn", "disk", "homebrew", "uninstaller", "leftovers"]
        let utilities = ["uninstaller", "homebrew", "leftovers", "disk"]
        XCTAssertEqual(ModuleOrder.apply(saved: saved, to: utilities),
                       ["disk", "homebrew", "uninstaller", "leftovers"])
    }

    func testUnarrangedCategoryKeepsRegistryOrder() {
        let utilities = ["uninstaller", "homebrew", "leftovers", "disk"]
        XCTAssertEqual(ModuleOrder.apply(saved: [], to: utilities), utilities)
    }

    /// A module the user has never dragged sorts after the ones they have,
    /// never in front of them.
    func testNewModuleLandsAfterArrangedOnes() {
        let saved = ["disk", "homebrew"]
        let utilities = ["uninstaller", "homebrew", "leftovers", "disk"]
        XCTAssertEqual(ModuleOrder.apply(saved: saved, to: utilities),
                       ["disk", "homebrew", "uninstaller", "leftovers"])
    }
}
