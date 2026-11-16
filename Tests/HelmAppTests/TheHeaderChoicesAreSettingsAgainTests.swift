import HelmRuntime
import HelmUI
import XCTest
@testable import HelmApp

/// **The page header's two choices are settings again, and the launch purge no longer deletes them.**
///
/// `module.app.pageBarStyle` and `module.app.toolbarSwitcherStyle` were listed in `ObsoleteDefaults.retired`
/// while the header row had no such choices; a key still listed is purged at the next launch, which is
/// indistinguishable from never having restored it. `ObsoleteDefaultsTests` scans only `Sources/HelmApp` for
/// the literal, so this is where the two spellings are put side by side.
@MainActor
final class TheHeaderChoicesAreSettingsAgainTests: XCTestCase {

    func testTheRestoredHeaderKeysAreNoLongerRetired() {
        for key in ["module.app." + PageBarStyle.storageKey, "module.app." + ToolbarSwitcherStyle.storageKey] {
            XCTAssertFalse(ObsoleteDefaults.retired.contains(key), """
                \(key) is a setting again and is still on the purge list, so the launch \
                after the one that saves it deletes it.
                """)
        }
    }

    func testAChoiceSurvivesTheLaunchPurge() {
        let store = InMemoryKeyValueStore()
        store.raw = ["module.app.pageBarStyle": "windowTitle", "module.app.toolbarSwitcherStyle": "icons"]
        AppSettings.migrateAndPurge(in: store)
        let app = AppSettings.store.over(store)
        XCTAssertEqual(AppSettings.pageBarStyle(in: app), .windowTitle)
        XCTAssertEqual(AppSettings.toolbarSwitcherStyle(in: app), .icons)
    }

    func testTheLongGoneFourthSpellingReadsAsText() {
        XCTAssertEqual(ToolbarSwitcherStyle(stored: "iconsNamingSelected"), .text)
        XCTAssertEqual(PageBarStyle(stored: "nonsense"), .moduleName)
    }

    func testAWriteEqualToTheStoredValueIsRefused() {
        let store = InMemoryKeyValueStore()
        let app = AppSettings.store.over(store)
        var posted = 0
        let token = NotificationCenter.default.addObserver(forName: .helmHeaderChoicesChanged, object: nil,
                                                           queue: nil) { _ in posted += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        AppSettings.setPageBarStyle(.moduleName, in: app)
        AppSettings.setToolbarSwitcherStyle(.text, in: app)
        XCTAssertEqual(posted, 0, "writing the value already read posted a change")
        AppSettings.setPageBarStyle(.windowTitle, in: app)
        AppSettings.setToolbarSwitcherStyle(.iconsAndText, in: app)
        XCTAssertEqual(posted, 2)
        XCTAssertEqual(AppSettings.pageBarStyle(in: app), .windowTitle)
    }
}
