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
}
