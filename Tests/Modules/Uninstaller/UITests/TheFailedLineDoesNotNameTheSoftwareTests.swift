import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The view model's «failed to trash» line is the second place an app's name
/// reached the log.** `Redact.path` strips the home prefix and nothing else; the
/// leaf of these paths is an app's name or a bundle id.
///
/// **And fed a leftover rather than a bundle.** The common leftover is a folder
/// named by a bundle id with no extension of its own —
/// `~/Library/Containers/com.acme.SecretTool` — and the redaction reads the id's
/// last dot as the extension, so the part of the id that names the product stays in
/// the line. The line is asserted written before its content is judged.
@MainActor
final class TheFailedLineDoesNotNameTheSoftwareTests: XCTestCase {

    override func setUp() {
        super.setUp()
        tailTheLog()
    }

    private var logged: [String] {
        loggedLines(UninstallerEngine.moduleID)
    }

    /// Loads, ticks, reviews and removes `app`, the removal failing on `failing` and
    /// trashing `trashed`; the lines the engine's module logged along the way.
    private func failedLine(_ app: InstalledApp, failing: String, trashed: [String]) async -> [String] {
        let work = AnsweringWork(
            apps: [app],
            scans: [app.bundleID: ScanResult(leftovers: [], runningNow: false)],
            removal: UninstallResult(trashed: trashed, freedBytes: 0,
                                     failures: [TrashFailureInfo(path: failing,
                                                                 reason: .needsFullDiskAccess,
                                                                 message: "denied")]))
        let model = modelOver(work)
        await model.loadAppsIfNeeded()
        model.setChecked(app, true)
        await model.prepareReview()
        await model.removeSelection()
        return logged
    }

    func testAFailedRemovalIsLoggedWithoutTheAppsName() async {
        let secret = "Secret Name \(UUID().uuidString.prefix(6))"
        let app = InstalledApp(name: secret, bundleID: "com.secret.vendor",
                               path: "/Applications/\(secret).app")
        let logged = await failedLine(app, failing: app.path, trashed: [])

        XCTAssertTrue(logged.contains { $0.hasPrefix("failed to trash:") },
                      "the failure line was not written, so an absence proves nothing: \(logged)")
        XCTAssertFalse(logged.contains { $0.contains(secret) },
                       "the log names the application: \(logged)")
    }

    func testAFailedLeftoverIsLoggedWithoutTheProductsName() async {
        let secret = "SecretTool\(UUID().uuidString.prefix(6))"
        let id = "com.acme.\(secret)"
        let app = InstalledApp(name: "Plain App", bundleID: id,
                               path: "/Applications/Plain App.app")
        let logged = await failedLine(app, failing: NSHomeDirectory() + "/Library/Containers/\(id)",
                                      trashed: [app.path])

        XCTAssertTrue(logged.contains { $0.hasPrefix("failed to trash:") },
                      "the failure line was not written, so an absence proves nothing: \(logged)")
        XCTAssertFalse(logged.contains { $0.contains(secret) },
                       "the log names the product: \(logged)")
    }
}
