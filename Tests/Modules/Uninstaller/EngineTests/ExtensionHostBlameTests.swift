import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// When a bundle refuses to move, the engine decides whether to blame an active
/// system extension by testing the app's bundle id against the extension hosts
/// with `hasPrefix`. A bundle id is dot-separated, and `hasPrefix` does not know
/// that: "at.obdev.littlesnitchmini" starts with "at.obdev.littlesnitch". This
/// is the identifier form of a path pasted onto its parent without the
/// separator — the same shape as a path joined onto "/".
///
/// The cost is not cosmetic. `.activeSystemExtension` and
/// `.needsFullDiskAccess` drive different buttons on the failure sheet, so the
/// wrong verdict sends the user to disable an extension that is not theirs
/// while the real remedy stays hidden.
private final class BlamingTrash: TrashPort, @unchecked Sendable {
    func trashItem(_ url: URL) -> TrashOutcome {
        // 513 = NSFileWriteNoPermissionError, what macOS returns for a bundle
        // it will not move.
        TrashOutcome(succeeded: false, errorCode: 513, message: "denied")
    }
}
private struct HostsExtension: SystemExtensionPort {
    let hosts: Set<String>
    func activeExtensionHosts() -> Set<String> { hosts }
    func installedExtensions() -> [SystemExtensionInfo] { [] }
}
private struct AnyFS: FileSystemPort {
    func exists(_ url: URL) -> Bool { true }
    func size(_ url: URL) -> Int { 0 }
    func glob(_ pattern: URL) -> [URL] { [] }
    func children(of url: URL) -> [URL] { [] }
}
private struct NoLister: AppLister {
    func installedApps() -> [InstalledApp] { [] }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
    func installedBundleIDs() -> Set<String> { [] }
    func isKnownToSystem(bundleID: String) -> Bool { false }
}
private struct NothingRunning: RunningAppsPort {
    func isRunning(bundleID: String) -> Bool { false }
    func quit(bundleID: String, force: Bool) {}
}

final class ExtensionHostBlameTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-blame-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes a minimal app bundle whose Info.plist the engine can read.
    private func makeApp(named name: String, bundleID: String) throws -> String {
        let app = root.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try (["CFBundleIdentifier": bundleID] as NSDictionary)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return app.path
    }

    private func engine(hosts: Set<String>) -> UninstallerEngine {
        UninstallerEngine(home: root, apps: NoLister(), fs: AnyFS(),
                          trash: BlamingTrash(), running: NothingRunning(),
                          extensions: HostsExtension(hosts: hosts))
    }

    /// Both apps ship, both ids are real products. Only the first owns the
    /// extension; the second merely starts with its id.
    func test_an_app_whose_id_merely_starts_with_a_host_id_is_not_blamed_on_it() async throws {
        let path = try makeApp(named: "Little Snitch Mini", bundleID: "at.obdev.littlesnitchmini")
        let result = try await engine(hosts: ["at.obdev.littlesnitch"])
            .uninstall(appPath: path, paths: [])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertNotEqual(result.failures.first?.reason,
                          TrashFailure.Reason.activeSystemExtension.rawValue,
                          "blamed an extension belonging to a different app")
        XCTAssertEqual(result.failures.first?.reason, TrashFailure.Reason.noPermission.rawValue)
    }

    /// Control: the app that really owns the extension must still be named,
    /// including through the "host id plus one component" case the parser emits.
    func test_the_app_that_owns_the_extension_is_still_blamed_on_it() async throws {
        let path = try makeApp(named: "Little Snitch", bundleID: "at.obdev.littlesnitch")
        let result = try await engine(hosts: ["at.obdev.littlesnitch"])
            .uninstall(appPath: path, paths: [])
        XCTAssertEqual(result.failures.first?.reason,
                       TrashFailure.Reason.activeSystemExtension.rawValue)
    }

    /// And an app with no relation to any host keeps the honest reason.
    func test_an_unrelated_app_keeps_the_permission_reason() async throws {
        let path = try makeApp(named: "Unrelated", bundleID: "com.example.unrelated")
        let result = try await engine(hosts: ["at.obdev.littlesnitch"])
            .uninstall(appPath: path, paths: [])
        XCTAssertEqual(result.failures.first?.reason, TrashFailure.Reason.noPermission.rawValue)
    }
}
