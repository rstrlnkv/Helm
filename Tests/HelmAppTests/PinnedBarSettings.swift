import Foundation
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The settings the bar a row builds reads, set the same way for each run and put back when the test
/// ends.** The callers build a `SettingsToolbar` (the toolbar the Settings window wears) and read no width or
/// cell of it: the pin makes the run the same each time, not because the subject is the look.
///
/// A bar reads `pageBarStyle`, `sidebarStyle`, `alwaysCollapseSearch` and `barAppearance` when it is
/// built and its tabs read `toolbarSwitcherStyle` (`SettingsToolbar` reads it in
/// `wholeTabsWidth(_:_:)` and in the tabs snapshot it keeps). The pin sets the ones that would change what
/// a bar measures: the words-only label style, the
/// module name in the bar, a search that does not always collapse, the flat look. The stored values are
/// read raw, so a key the domain did not hold is removed again rather than written back as the typed
/// getter's default.
enum PinnedBarSettings {

    @MainActor
    static func pin(in test: XCTestCase) {
        let store = AppSettings.store
        let keys = [ToolbarSwitcherStyle.storageKey, PageBarStyle.storageKey, "alwaysCollapseSearch",
                    HelmBarAppearance.storageKey]
        let found = keys.map { store.object($0) }
        test.addTeardownBlock { @MainActor in
            for (key, value) in zip(keys, found) { store.set(value, for: key) }
            NotificationCenter.default.post(name: .helmToolbarSwitcherStyleChanged, object: nil)
            NotificationCenter.default.post(name: .helmBarAppearanceChanged, object: nil)
        }
        AppSettings.toolbarSwitcherStyle = .text
        AppSettings.pageBarStyle = .moduleName
        AppSettings.alwaysCollapseSearch = false
        AppSettings.barAppearance = .flat
    }
}
