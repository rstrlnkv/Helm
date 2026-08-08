import XCTest
import HelmContract
import HelmUI
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// Safari, listed at "0 Б", with a checkbox.
///
/// The row now leaves the checkbox out and says "System", the way Disk marks a
/// row it may not remove. The row is a view, so what is pinned here is the
/// half a test can hold: the only door into the ticked set refuses to open for
/// a `com.apple.` identifier. A checkbox that stops being drawn while the set
/// still accepts the id is one tap gesture away from the same bug.
@MainActor
final class SystemAppIsNotOfferedTests: XCTestCase {

    private struct SilentFS: FileSystemPort {
        func exists(_ url: URL) -> Bool { false }
        func size(_ url: URL) -> Int { 0 }
        func glob(_ pattern: URL) -> [URL] { [] }
        func children(of url: URL) -> [URL] { [] }
    }
    private struct FixedLister: AppLister {
        let apps: [InstalledApp]
        func installedApps() -> [InstalledApp] { apps }
        func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
        func installedBundleIDs() -> Set<String> { Set(apps.map(\.bundleID)) }
        func isKnownToSystem(bundleID: String) -> Bool { false }
    }

    private var engine: UninstallerEngine?

    private func viewModel() -> UninstallerViewModel {
        let engine = UninstallerEngine(
            home: URL(fileURLWithPath: "/Users/x"),
            apps: FixedLister(apps: [
                InstalledApp(name: "Safari", bundleID: "com.apple.Safari",
                             path: "/Applications/Safari.app", sizeBytes: 0),
                InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                             path: "/Applications/Tool.app", sizeBytes: 10),
            ]),
            fs: SilentFS(), trash: NoTrash(), running: NoRunning())
        self.engine = engine
        return UninstallerViewModel(vm: ModuleViewModel(transport: engine.transport))
    }

    func testASystemAppCannotBeTicked() {
        let uvm = viewModel()

        uvm.setChecked("com.apple.Safari", true)

        XCTAssertEqual(uvm.checked, [], "macOS will refuse it, after the scan and the click")
    }

    /// The tap on the row body, which is a second door into the same set.
    func testTappingTheRowDoesNotTickItEither() {
        let uvm = viewModel()

        uvm.toggleChecked("com.apple.Safari")

        XCTAssertEqual(uvm.checked, [])
    }

    /// And the app the person actually wants to remove still ticks.
    func testAnOrdinaryAppStillTicks() {
        let uvm = viewModel()

        uvm.toggleChecked("com.acme.tool")

        XCTAssertEqual(uvm.checked, ["com.acme.tool"])
    }
}
