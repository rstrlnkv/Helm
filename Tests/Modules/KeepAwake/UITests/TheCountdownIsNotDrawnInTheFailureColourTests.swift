import XCTest
import HelmRuntime
@testable import Module_KeepAwake_UI

/// The menu-bar icon while a timer runs.
///
/// It defaulted to `red`, and the reader that applies it is guarded by
/// `!isEmpty` under a comment saying it fires «when the user picked one» — a
/// stored tint is never empty, so it fired always. A session running perfectly
/// normally was painted in the colour this app uses for failure, and the page
/// drew two palettes ringed on two colours nobody had chosen.
final class TheCountdownIsNotDrawnInTheFailureColourTests: XCTestCase {
    private var store: NamespacedStore!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
    }

    func testAFreshInstallCountsDownInTheModulesOwnColour() {
        XCTAssertEqual(MenuBarLook.timerTint(store), "orange")
    }

    /// The two palettes on the page open on one answer, so neither ring is a
    /// colour somebody has to explain to themselves.
    func testBothPalettesOpenOnTheSameColour() {
        XCTAssertEqual(MenuBarLook.timerTint(store), MenuBarLook.activeTint(store))
    }

    /// And a colour that *was* chosen is still the one used — the point of the
    /// row existing at all.
    func testAChosenTimerColourIsKept() {
        store.set("green", for: MenuBarLook.Key.timerTint)
        XCTAssertEqual(MenuBarLook.timerTint(store), "green")
    }
}
