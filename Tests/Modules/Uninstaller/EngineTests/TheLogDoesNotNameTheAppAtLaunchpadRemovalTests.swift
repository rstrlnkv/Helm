import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// **The door's log lines name neither the app nor its id.** The name is what the person called it and
/// the id names somebody's habits (`Redact`); a refusal, a hold, a move and a failure each write a line,
/// and each is read for both.
final class TheLogDoesNotNameTheAppAtLaunchpadRemovalTests: XCTestCase {

    private let secret = "SecretApp\(UUID().uuidString.prefix(6))"
    private var id: String { "com.secret.\(secret.lowercased())" }
    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("launchpad-log")
        tailTheLog()
    }

    private func engine(trash: TrashPort, running: FakeRunning) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(), trash: trash, running: running)
    }

    private func assertSilentAbout(_ prefix: String, file: StaticString = #filePath, line: UInt = #line) {
        let lines = loggedLines(UninstallerEngine.moduleID)
        XCTAssertTrue(lines.contains { $0.hasPrefix(prefix) },
                      "no «\(prefix)» line was written, so an absence proves nothing: \(lines)",
                      file: file, line: line)
        XCTAssertFalse(lines.contains { $0.contains(secret) || $0.lowercased().contains(id) },
                       "the log names the app: \(lines)", file: file, line: line)
    }

    func testARefusalAHoldAMoveAndAFailureNameNothing() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/\(secret).app"), id: id)
        _ = try write("Library/Caches/\(id)/data", in: home)
        let candidate = AppRemovalCandidate(bundleID: id, path: path, name: secret)

        _ = await engine(trash: FakeTrash(), running: FakeRunning(running: []))
            .removeApp(AppRemovalCandidate(bundleID: "com.apple.\(secret)", path: path, name: secret),
                       quittingIfRunning: false)
        assertSilentAbout("app removal refused")

        _ = await engine(trash: FakeTrash(), running: FakeRunning(running: [id]))
            .removeApp(candidate, quittingIfRunning: false)
        assertSilentAbout("batch held")

        _ = await engine(trash: FakeTrash(failing: [path]), running: FakeRunning(running: []))
            .removeApp(candidate, quittingIfRunning: false)
        assertSilentAbout("trash refused")

        _ = await engine(trash: FakeTrash(), running: FakeRunning(running: []))
            .removeApp(candidate, quittingIfRunning: false)
        assertSilentAbout("app removal: ")
    }
}
