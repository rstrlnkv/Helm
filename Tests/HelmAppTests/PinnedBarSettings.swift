import Foundation
import AppKit
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The settings the bar a row builds reads, set the same way for each run and put back when the test
/// ends.** The callers build a `SettingsToolbar` (the toolbar the Settings window wears) and read no width or
/// cell of it; the look is the one thing a caller chooses (`pin(in:look:)`, Flat by default), because the search
/// item is a different object under each (AppKit's `NSSearchToolbarItem` under Liquid Glass, `ShellBarSearch`
/// under Flat) and the typing rows run under both.
///
/// A bar reads `pageBarStyle`, `sidebarStyle`, `alwaysCollapseSearch` and `barAppearance` when it is
/// built and its tabs read `toolbarSwitcherStyle` (`SettingsToolbar` reads it in
/// `wholeTabsWidth(_:_:)` and in the tabs snapshot it keeps). The pin sets the ones that would change what
/// a bar measures: the words-only label style, the
/// module name in the bar, a search that does not always collapse, and the look. The stored values are
/// read raw, so a key the domain did not hold is removed again rather than written back as the typed
/// getter's default.
enum PinnedBarSettings {

    @MainActor
    static func pin(in test: XCTestCase, look: HelmBarAppearance = .flat) {
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
        AppSettings.barAppearance = look
    }

    /// **The bar the fixture built is the look that was pinned**: Glass lists AppKit's `NSSearchToolbarItem`,
    /// Flat lists none (its search is Helm's own item). Without this a row run "under both looks" could be run
    /// twice under one.
    @MainActor
    static func assertWears(_ look: HelmBarAppearance, _ fixture: LivePageInTheToolbarFixture,
                            file: StaticString = #filePath, line: UInt = #line) {
        let items = fixture.mount.window?.toolbar?.items ?? []
        let glassItem = items.contains { $0 is NSSearchToolbarItem }
        XCTAssertEqual(glassItem, look == .liquidGlass,
                       "the bar pinned to \(look.rawValue) lists \(items.map { String(describing: type(of: $0)) })",
                       file: file, line: line)
    }
}
