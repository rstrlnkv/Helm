import Foundation
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The settings a `MountedPageBar` reads, set the way the rows that count the bar's measurements need
/// them, and put back when the test ends.**
///
/// The bar reads `pageBarStyle`, `sidebarStyle`, `alwaysCollapseSearch` and `barAppearance` when it is
/// built and its tabs zone reads `toolbarSwitcherStyle` on every show (`MountedPageBar`'s own doc). A row
/// that counts measurements pins the ones that change what is measured: the words-only label style, the
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

    /// Turns the run loop for `seconds` by the clock; a turn that returns on the first source it serves
    /// buys no time.
    @MainActor
    static func rest(_ seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }
}
