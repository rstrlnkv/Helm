import HelmRuntime
import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

private struct HostsExtension: SystemExtensionPort {
    let hosts: Set<String>
    /// A tool that answered. The silence (`nil`) is
    /// `ASilentToolIsNotNoExtensionsTests`' subject, not to be planted here.
    func activeExtensionHosts() -> Set<String>? { hosts }
}
/// A refused bundle is blamed on a live system extension only when its id is
/// the host's or extends it past a dot: "at.obdev.littlesnitchmini" starts with
/// "at.obdev.littlesnitch" and is another product. The two reasons drive
/// different buttons on the failure sheet.
final class ExtensionHostBlameTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("blame")
    }

    /// Writes a minimal app bundle whose Info.plist the engine can read.
    private func makeApp(named name: String, bundleID: String) throws -> String {
        try writeAppBundle(root.appendingPathComponent("\(name).app"), id: bundleID)
    }

    private func engine(hosts: Set<String>) -> UninstallerEngine {
        UninstallerEngine(home: root, apps: FakeApps(), fs: FakeFS(everyPathExistsAt: 0),
                          trash: RefusesEverything(), running: NoRunning(),
                          extensions: HostsExtension(hosts: hosts))
    }

    /// Both apps ship, both ids are real products. Only the first owns the
    /// extension; the second merely starts with its id.
    func test_an_app_whose_id_merely_starts_with_a_host_id_is_not_blamed_on_it() async throws {
        let path = try makeApp(named: "Little Snitch Mini", bundleID: "at.obdev.littlesnitchmini")
        let result = await engine(hosts: ["at.obdev.littlesnitch"])
            .trashPaths([path])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertNotEqual(result.failures.first?.reason,
                          TrashFailure.Reason.activeSystemExtension,
                          "blamed an extension belonging to a different app")
        XCTAssertEqual(result.failures.first?.reason, TrashFailure.Reason.noPermission)
    }

    /// Control: the app that really owns the extension must still be named,
    /// including through the "host id plus one component" case the parser emits.
    func test_the_app_that_owns_the_extension_is_still_blamed_on_it() async throws {
        let path = try makeApp(named: "Little Snitch", bundleID: "at.obdev.littlesnitch")
        let result = await engine(hosts: ["at.obdev.littlesnitch"])
            .trashPaths([path])
        XCTAssertEqual(result.failures.first?.reason,
                       TrashFailure.Reason.activeSystemExtension)
    }

    /// And an app with no relation to any host keeps the honest reason.
    func test_an_unrelated_app_keeps_the_permission_reason() async throws {
        let path = try makeApp(named: "Unrelated", bundleID: "com.example.unrelated")
        let result = await engine(hosts: ["at.obdev.littlesnitch"])
            .trashPaths([path])
        XCTAssertEqual(result.failures.first?.reason, TrashFailure.Reason.noPermission)
    }
}
