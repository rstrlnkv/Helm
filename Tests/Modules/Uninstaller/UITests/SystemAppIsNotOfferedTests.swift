import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// Safari, listed at "0 Б", with a checkbox.
///
/// The row now leaves the checkbox out and says "System app", the way Disk marks a
/// row it may not remove. The row is a view, so what is pinned here is the
/// half a test can hold: the only door into the ticked set refuses to open for
/// a `com.apple.` identifier. A checkbox that stops being drawn while the set
/// still accepts the id is one tap gesture away from the same bug.
@MainActor
final class SystemAppIsNotOfferedTests: XCTestCase {

    private let safari = InstalledApp(name: "Safari", bundleID: "com.apple.Safari",
                                      path: "/Applications/Safari.app", sizeBytes: 0)
    private let tool = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                    path: "/Applications/Tool.app", sizeBytes: 10)

    private func viewModel() -> UninstallerViewModel {
        let engine = UninstallerEngine(
            home: URL(fileURLWithPath: "/Users/x"),
            apps: FakeApps(apps: [
                safari, tool,
            ]),
            fs: NoFiles(), trash: NoTrash(), running: NoRunning())
        return modelOver(engine)
    }

    func testASystemAppCannotBeTicked() {
        let uvm = viewModel()

        uvm.setChecked(safari, true)

        XCTAssertEqual(uvm.checked, [], "macOS will refuse it, after the scan and the click")
    }

    /// The tap on the row body, which is a second door into the same set.
    func testTappingTheRowDoesNotTickItEither() {
        let uvm = viewModel()

        uvm.toggleChecked(safari)

        XCTAssertEqual(uvm.checked, [])
    }

    /// And the app the person actually wants to remove still ticks.
    func testAnOrdinaryAppStillTicks() {
        let uvm = viewModel()

        uvm.toggleChecked(tool)

        XCTAssertEqual(uvm.checked, [tool.path])
    }
}
