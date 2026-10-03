import Foundation
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// What the panel's timer cell writes: a press with the timer off switches it on with the last length, a length picked
/// in its menu is the next such press's, and none switches it off and leaves the length alone. The cell and the menus
/// draw from the model, which writes the module's keys `timer` and `timerLength`.
@MainActor
final class TheTimerCellSwitchesOnWithTheLastLengthTests: XCTestCase {

    private func model(_ values: [String: Any] = [:]) -> (CapturePanelModel, NamespacedStore) {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        for (key, value) in values { store.set(value, for: key) }
        return (CapturePanelModel(store: store), store)
    }

    /// The cell calls `toggleTimer()` only while the timer is off; with it on a press opens the lengths, and «No timer»
    /// there is `choose(.none)`.
    func testAPressWithTheTimerOffSwitchesOnWithTheLastLengthAndNoTimerSwitchesOff() {
        let (model, store) = model([ScreenshotsSettings.Key.timerLength: 30])
        XCTAssertFalse(model.timerOn)
        model.toggleTimer()
        XCTAssertEqual(model.settings.timer, .thirty)
        XCTAssertEqual(store.int(ScreenshotsSettings.Key.timer, default: -1), 30)
        model.choose(.none)
        XCTAssertEqual(model.settings.timer, .none)
        XCTAssertEqual(model.settings.timerLength, .thirty, "switching off forgot the length")
        model.toggleTimer()
        XCTAssertEqual(model.settings.timer, .thirty)
    }

    func testALengthPickedInTheMenuIsTheNextSwitchingOn() {
        let (model, _) = model()
        model.toggleTimer()
        XCTAssertEqual(model.settings.timer, .five)
        model.choose(.ten)
        XCTAssertEqual(model.settings.timerLength, .ten)
        model.choose(.none)
        XCTAssertEqual(model.settings.timer, .none)
        XCTAssertEqual(model.settings.timerLength, .ten, "None is not a length")
        model.toggleTimer()
        XCTAssertEqual(model.settings.timer, .ten)
    }

    func testAStoreFromBeforeTheLengthSwitchesOnWithWhatTheTimerHeld() {
        let (model, _) = model([ScreenshotsSettings.Key.timer: 10])
        XCTAssertTrue(model.timerOn)
        model.choose(.none)
        model.toggleTimer()
        XCTAssertEqual(model.settings.timer, .ten)
    }

    func testTheTimerMenuListsFiveTenThirtyAndNoneWithTheCurrentOneChecked() {
        let (model, _) = model([ScreenshotsSettings.Key.timer: 10])
        let menu = PanelMenus.timer(model.settings.timer) { model.choose($0) }
        // `NSMenuItem` turns an unbreakable space into a plain one in its title (measured: 5 NBSP x reads back 5 space x).
        let plain = { (text: String) in text.replacingOccurrences(of: "\u{00A0}", with: " ") }
        let entries = menu.items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(entries.map(\.title), [ScStr.timer(.five), ScStr.timer(.ten), ScStr.timer(.thirty), ScStr.timer(.none)].map(plain))
        XCTAssertEqual(entries.map { $0.state == .on }, [false, true, false, false])
        XCTAssertEqual(menu.items.map(\.isSeparatorItem), [false, false, false, true, false], "None is not set apart from the lengths")
        _ = entries[2].target?.perform(entries[2].action, with: entries[2])
        XCTAssertEqual(model.settings.timer, .thirty, "the menu's item did not write its length")
    }

    func testTheGearMenuHasNoTimerAndHasThePanelsWayBack() {
        let (model, store) = model([ScreenshotsSettings.Key.panelOffsetX: 40.0, ScreenshotsSettings.Key.panelOffsetY: -9.0])
        let titles = PanelMenus.options(model).items.map(\.title)
        for length in CaptureTimer.allCases { XCTAssertFalse(titles.contains(ScStr.timer(length)), "the timer is back in Options: \(length)") }
        XCTAssertFalse(titles.contains(ScStr.timer))
        XCTAssertTrue(titles.contains(ScStr.putPanelBack))
        let back = try? XCTUnwrap(PanelMenus.options(model).items.first { $0.title == ScStr.putPanelBack })
        _ = back?.target?.perform(back?.action, with: back)
        XCTAssertNil(store.object(ScreenshotsSettings.Key.panelOffsetX))
        XCTAssertNil(store.object(ScreenshotsSettings.Key.panelOffsetY))
        XCTAssertEqual(model.settings.panelOffset, .zero)
    }
}
