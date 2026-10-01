import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The view model's «failed to trash» line is the second place an app's name
/// reached the log.** `Redact.paths` strips the home prefix and nothing else; the
/// leaf of these paths is an app's name or a bundle id.
@MainActor
final class TheFailedLineDoesNotNameTheAppTests: XCTestCase {

    private let secret = "Secret Name \(UUID().uuidString.prefix(6))"

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

    func testAFailedRemovalIsLoggedWithoutTheAppsName() async {
        let app = InstalledApp(name: secret, bundleID: "com.secret.vendor",
                               path: "/Applications/\(secret).app", sizeBytes: 4_096)
        let wire = UninstallerWire(
            apps: [app],
            scans: [app.bundleID: ScanResult(bundleID: app.bundleID, appPath: app.path,
                                             appSizeBytes: 0, leftovers: [], runningNow: false)],
            removal: UninstallResult(trashed: [], freedBytes: 0,
                                     failures: [TrashFailureInfo(path: app.path,
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
                       "the log names the application: \(logged)")
    }
}
