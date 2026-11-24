import HelmRuntime
import HelmUI
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **The page header's three choices are settings again, and the launch purge no longer deletes them.**
///
/// `module.app.pageBarStyle`, `module.app.toolbarSwitcherStyle` and `module.app.alwaysCollapseSearch` were listed in `ObsoleteDefaults.retired`
/// while the header row had no such choices; a key still listed is purged at the next launch, which is
/// indistinguishable from never having restored it. `ObsoleteDefaultsTests` scans only `Sources/HelmApp` for
/// the literal, so this is where the spellings are put side by side.
@MainActor
final class TheHeaderChoicesAreSettingsAgainTests: XCTestCase {

    func testTheRestoredHeaderKeysAreNoLongerRetired() {
        for key in ["module.app." + PageBarStyle.storageKey, "module.app." + HeaderTabLabels.storageKey,
                    "module.app.alwaysCollapseSearch"] {
            XCTAssertFalse(ObsoleteDefaults.retired.contains(key), """
                \(key) is a setting again and is still on the purge list, so the launch \
                after the one that saves it deletes it.
                """)
        }
    }

    func testAChoiceSurvivesTheLaunchPurge() {
        let store = InMemoryKeyValueStore()
        store.raw = ["module.app.pageBarStyle": "windowTitle", "module.app.toolbarSwitcherStyle": "icons",
                     "module.app.alwaysCollapseSearch": true]
        ObsoleteDefaults.purge(from: store)
        let app = AppSettings.store.over(store)
        XCTAssertEqual(AppSettings.pageBarStyle(in: app), .windowTitle)
        XCTAssertEqual(AppSettings.tabLabels(in: app), .icons)
        XCTAssertTrue(AppSettings.alwaysCollapseSearch(in: app))
    }

    func testTheLongGoneFourthSpellingReadsAsText() {
        XCTAssertEqual(HeaderTabLabels(stored: "iconsNamingSelected"), .text)
        XCTAssertEqual(PageBarStyle(stored: "nonsense"), .moduleName)
    }

    func testAWriteEqualToTheStoredValueIsRefused() {
        let store = InMemoryKeyValueStore()
        let app = AppSettings.store.over(store)
        let posted = LockedCount()
        let token = NotificationCenter.default.addObserver(forName: .helmHeaderChoicesChanged, object: nil,
                                                           queue: nil) { _ in posted.bump() }
        defer { NotificationCenter.default.removeObserver(token) }
        AppSettings.setPageBarStyle(.moduleName, in: app)
        AppSettings.setTabLabels(.text, in: app)
        AppSettings.setAlwaysCollapseSearch(false, in: app)
        XCTAssertEqual(posted.value, 0, "writing the value already read posted a change")
        AppSettings.setPageBarStyle(.windowTitle, in: app)
        AppSettings.setTabLabels(.iconsAndText, in: app)
        AppSettings.setAlwaysCollapseSearch(true, in: app)
        XCTAssertEqual(posted.value, 3)
        XCTAssertTrue(AppSettings.headerChoices.collapseSearch == AppSettings.alwaysCollapseSearch)
        XCTAssertEqual(AppSettings.pageBarStyle(in: app), .windowTitle)
    }
}
