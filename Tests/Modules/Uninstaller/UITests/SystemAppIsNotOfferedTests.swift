import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// A `com.apple.` app cannot be ticked. The row leaves the checkbox out and
/// says "System app"; the row is a view, so this pins the half a test can
/// hold: the only door into the ticked set refuses the id.
@MainActor
final class SystemAppIsNotOfferedTests: XCTestCase {

    private let safari = InstalledApp(name: "Safari", bundleID: "com.apple.Safari",
                                      path: "/Applications/Safari.app")
    private let tool = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                    path: "/Applications/Tool.app")

    private func viewModel() -> UninstallerViewModel {
        let engine = UninstallerEngine(
            home: URL(fileURLWithPath: "/Users/x"),
            apps: FakeApps(apps: [
                safari, tool,
            ]),
            fs: FakeFS(), trash: NoTrash(), running: NoRunning())
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
