import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The fold state and the expanded width are read from the app's store under `module.app.sidebarCollapsed` and
/// `module.app.sidebarWidth`; a person's flip writes the state; the next window opens as it was left.** Every store
/// here is a scratch one, built over memory, never the process's defaults; no window is shown and nothing waits.
@MainActor
final class TheSidebarsFoldIsRememberedTests: XCTestCase {

    private let backing = InMemoryKeyValueStore()
    private lazy var store = AppSettings.store.over(backing)

    private func controller() -> SettingsShellViewController {
        let c = SettingsShellViewController(model: SettingsModel(host: ModuleHost.shared),
                                            toolbarChannel: HelmWindowToolbarChannel(), band: .onMacOS(27),
                                            bar: ShellPageBarView(), store: store)
        c.shell.reducesMotion = { true }
        c.loadViewIfNeeded()
        c.shell.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        c.shell.layoutSubtreeIfNeeded()
        return c
    }

    /// Per stored value: nothing, a string, and the numbers 2 and 1; only `true` and a number 1 read as folded (a
    /// number comes back as the property list would give it, where 1 is a `Bool`). Total failure prints: "an empty
    /// store read as folded" / "a stored true read back as expanded" / "the state was <v> under
    /// module.app.sidebarCollapsed" / "a stored false read back as folded" / "a string read as folded: ..." /
    /// "a stored number 2 read as folded" / "a stored number 1 read as expanded".
    func testTheFoldStateRoundTrips() {
        XCTAssertFalse(AppSettings.sidebarCollapsed(in: store), "an empty store read as folded")
        AppSettings.setSidebarCollapsed(true, in: store)
        XCTAssertTrue(AppSettings.sidebarCollapsed(in: store), "a stored true read back as expanded")
        XCTAssertEqual(backing.object(forKey: "module.app.sidebarCollapsed") as? Bool, true,
                       "the state was \(String(describing: backing.object(forKey: "module.app.sidebarCollapsed"))) under module.app.sidebarCollapsed")
        AppSettings.setSidebarCollapsed(false, in: store)
        XCTAssertFalse(AppSettings.sidebarCollapsed(in: store), "a stored false read back as folded")

        store.set("true", for: "sidebarCollapsed")
        XCTAssertFalse(AppSettings.sidebarCollapsed(in: store), "a string read as folded: only a Bool is a state")
        store.set(2, for: "sidebarCollapsed")
        XCTAssertFalse(AppSettings.sidebarCollapsed(in: store), "a stored number 2 read as folded")
        store.set(1, for: "sidebarCollapsed")
        XCTAssertTrue(AppSettings.sidebarCollapsed(in: store), "a stored number 1 read as expanded")
    }

    /// Per value: not-a-number reads the default 200 because nobody knows which end it meant; an infinity reads
    /// the bound of its side; a finite value is brought into 150...320; a missing key or a string reads 200.
    /// Total failure prints: "<case> read as <w>, not <want>".
    func testAStoredWidthIsBroughtIntoTheRange() {
        let cases: [(String, Any?, CGFloat)] = [
            ("not-a-number", Double.nan, 200),
            ("+infinity", Double.infinity, 320),
            ("-infinity", -Double.infinity, 150),
            ("40", 40.0, 150),
            ("4000", 4000.0, 320),
            ("233.5", 233.5, 233.5),
            ("a string", "wide", 200),
            ("no key", nil, 200)]
        for (name, stored, want) in cases {
            store.set(stored, for: "sidebarWidth")
            let read = AppSettings.sidebarWidth(in: store)
            XCTAssertEqual(read, want, "\(name) read as \(read), not \(want)")
        }
        XCTAssertEqual(ShellGeometry.sidebarRange, 150...320, "the range this row is written against moved")
    }

    /// Total failure prints: "after a flip the store held <v>" / "the next window opened expanded after a flip to
    /// the rail" / "the next window opened <w> wide, not the rail's <r>" / "a window over a stored false opened
    /// folded" / "a stored 260 opened <w> wide" / "a stored not-a-number did not open at the default" / "a stored
    /// 4000 did not open at the upper bound".
    func testAFlipIsWrittenAndTheNextWindowOpensAsItWasLeft() {
        let a = controller()
        a.flipSidebar()
        XCTAssertEqual(backing.object(forKey: "module.app.sidebarCollapsed") as? Bool, true,
                       "after a flip the store held \(String(describing: backing.object(forKey: "module.app.sidebarCollapsed")))")

        let b = controller()
        XCTAssertTrue(b.sidebarCollapsed, "the next window opened expanded after a flip to the rail")
        XCTAssertEqual(b.shell.sidebarWidth, ShellGeometry.railWidth,
                       "the next window opened \(b.shell.sidebarWidth) wide, not the rail's \(ShellGeometry.railWidth)")

        AppSettings.setSidebarCollapsed(false, in: store)
        store.set(260.0, for: "sidebarWidth")
        let c = controller()
        XCTAssertFalse(c.sidebarCollapsed, "a window over a stored false opened folded")
        XCTAssertEqual(c.shell.sidebarWidth, 260, "a stored 260 opened \(c.shell.sidebarWidth) wide")

        store.set(Double.nan, for: "sidebarWidth")
        XCTAssertEqual(controller().shell.sidebarWidth, 200, "a stored not-a-number did not open at the default")
        store.set(4000.0, for: "sidebarWidth")
        XCTAssertEqual(controller().shell.sidebarWidth, 320, "a stored 4000 did not open at the upper bound")
    }

    /// The width the stored value gave is where an unfold ends. Total failure prints: "the unfold was asked as
    /// <folds>, not to 260".
    func testTheUnfoldEndsAtTheStoredWidth() {
        AppSettings.setSidebarCollapsed(true, in: store)
        store.set(260.0, for: "sidebarWidth")
        var heard: [ShellContentView.Fold] = []
        let c = SettingsShellViewController(model: SettingsModel(host: ModuleHost.shared),
                                            toolbarChannel: HelmWindowToolbarChannel(), band: .onMacOS(27),
                                            bar: ShellPageBarView(), store: store)
        c.shell.reducesMotion = { false }
        c.shell.onFold = { heard.append($0) }
        c.loadViewIfNeeded()
        XCTAssertEqual(c.shell.sidebarWidth, ShellGeometry.railWidth, "the window did not open in the rail: the fixture is wrong")
        c.flipSidebar()
        XCTAssertEqual(heard, [ShellContentView.Fold(from: ShellGeometry.railWidth, to: 260, duration: HelmMotion.sidebarFoldDuration)],
                       "the unfold was asked as \(heard), not to 260")
        XCTAssertEqual(AppSettings.sidebarWidth(in: store), 260, "the flip rewrote the stored width")
    }
}
