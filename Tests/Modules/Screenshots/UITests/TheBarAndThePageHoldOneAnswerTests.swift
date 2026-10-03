import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The panel's gear menu and the settings page write some of the same keys (where it is saved, the thumbnail, the
/// cursor), so neither may go on showing an answer the other has replaced.** The bar is a
/// non-activating panel at status-bar level and the settings window is an
/// ordinary one: both are on screen at once whenever somebody tries the bar
/// with Settings still open. A switch the bar turned on that the page still
/// draws as off is a page telling the person the opposite of what the next
/// capture will do — and the page's next press of that switch writes its own
/// stale idea back.
///
/// The page is mounted offscreen and never ordered in; the bar is its model
/// alone, writing the store exactly as its menu does. Nothing reaches a real
/// screen.
@MainActor
final class TheBarAndThePageHoldOneAnswerTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private func mount(_ store: NamespacedStore) -> MountedRender {
        AppLanguage.override = .en
        let transport = LocalTransport()
        transport.emit(ScreenshotsEvent.screenshotsState, encoding: ScreenshotsPageRender.untouched)
        let mount = MountedRender(
            ScreenshotsSettingsPage(vm: ModuleViewModel(transport: transport), store: store)
                .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted,
                                                      screenRecording: .granted)),
            width: 744, height: 900, appearance: .aqua)
        mount.settle(40)
        return mount
    }

    /// The page's switches top to bottom: thumbnail, shutter sound, pointer.
    private func switches(_ mount: MountedRender) -> [Bool] {
        mount.host.everyView(ofType: NSSwitch.self)
            .sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
            .map { $0.state == .on }
    }

    /// The control first — a page mounted after the bar wrote draws what the bar
    /// wrote, so the reading below can see the switch at all — then the case:
    /// a page already up while the bar writes.
    func testAPointerSwitchTurnedOnFromTheBarIsOnOnThePageThatIsUp() throws {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())

        let control = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        CapturePanelModel(store: control).setCursor(true)
        let after = switches(mount(control))
        XCTAssertEqual(after.count, 3, "the page no longer draws three switches, so this reads nothing: \(after)")
        XCTAssertEqual(after.last, true, "a page mounted after the bar turned the pointer on does not draw it on")

        let page = mount(store)
        XCTAssertEqual(switches(page).last, false, "the pointer switch was on before anybody turned it on")
        let bar = CapturePanelModel(store: store)
        bar.setCursor(true)
        XCTAssertTrue(ScreenshotsSettings.read(store).showCursor, "the bar did not write the setting")
        page.settle(40)
        XCTAssertEqual(switches(page).last, true,
                       "the bar turned «Show mouse pointer» on and the settings page that was up still draws it off")
    }

    /// The other direction: the bar is up while the page changes a setting its
    /// menu shows. The menu draws `settings`, which is read at `show()` only.
    func testABarThatIsUpShowsWhatThePageWroteAfterItOpened() {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let bar = CapturePanelModel(store: store)
        XCTAssertEqual(bar.settings.saveTarget, .macOS)
        // What the page's «Save to» picker writes.
        store.set(SaveTarget.clipboard.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        XCTAssertEqual(ScreenshotsSettings.read(store).saveTarget, .clipboard, "the page's write did not land")
        XCTAssertEqual(bar.settings.saveTarget, .clipboard,
                       "the bar's menu still ticks the target the page has replaced")
    }

    /// The bar's "Remember last selection" switched off erases the stored area:
    /// it goes through the engine's one door, and a record left behind would
    /// come back stale when the switch is turned on again.
    func testTheBarSwitchingRememberOffErasesTheStoredSelection() throws {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let model = CapturePanelModel(store: store)
        model.setRemember(true)
        try XCTUnwrap(RememberedSelection(display: "AAAA-1111", rect: CGRect(x: 10, y: 20, width: 300, height: 200)))
            .write(to: store)
        XCTAssertNotNil(RememberedSelection.read(store), "nothing was written, so nothing below proves an erase")
        model.setRemember(false)
        XCTAssertNil(RememberedSelection.read(store))
        XCTAssertFalse(model.settings.rememberSelection)
    }
}
