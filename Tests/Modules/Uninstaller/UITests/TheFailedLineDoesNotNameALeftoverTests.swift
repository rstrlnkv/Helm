import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The view model's «failed to trash» line, fed a leftover rather than a
/// bundle.** The common leftover is a folder named by a bundle id with no
/// extension of its own — `~/Library/Containers/com.acme.SecretTool` — and the
/// redaction reads the id's last dot as the extension, so the part of the id that
/// names the product stays in the line. The line is asserted written before its
/// content is judged.
@MainActor
final class TheFailedLineDoesNotNameALeftoverTests: XCTestCase {

    private let secret = "SecretTool\(UUID().uuidString.prefix(6))"

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var logged: [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == UninstallerEngine.moduleID }
            .map(\.message)
    }

    func testAFailedLeftoverIsLoggedWithoutTheProductsName() async {
        let id = "com.acme.\(secret)"
        let app = InstalledApp(name: "Plain App", bundleID: id,
                               path: "/Applications/Plain App.app", sizeBytes: 4_096)
        let leftover = NSHomeDirectory() + "/Library/Containers/\(id)"
        let wire = UninstallerWire(
            apps: [app],
            scans: [app.bundleID: ScanResult(bundleID: app.bundleID, appPath: app.path,
                                             appSizeBytes: 0, leftovers: [], runningNow: false)],
            removal: UninstallResult(trashed: [app.path], freedBytes: 0,
                                     failures: [TrashFailureInfo(path: leftover,
                                                                 reason: .needsFullDiskAccess,
                                                                 message: "denied")]))
        let model = UninstallerViewModel(vm: ModuleViewModel(transport: wire))
        await model.loadAppsIfNeeded()
        model.setChecked(app.bundleID, true)
        await model.prepareReview()
        await model.removeSelection()

        XCTAssertTrue(logged.contains { $0.hasPrefix("failed to trash:") },
                      "the failure line was not written, so an absence proves nothing: \(logged)")
        XCTAssertFalse(logged.contains { $0.contains(secret) },
                       "the log names the product: \(logged)")
    }
}
