import Foundation
import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// **A refused trash of an application is logged, and the log must not carry the
/// application's name.** The last component of an app bundle is what the person
/// called it, and of a leftover a bundle id; the shared removal loop writes a line
/// for every refusal and has to be told which kind of leaf it is holding.
final class TheLogDoesNotNameTheAppTests: XCTestCase {

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

    func testARefusedAppIsLoggedWithoutItsName() async {
        let path = "/Applications/\(secret).app"
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"), apps: FakeApps(),
                                       fs: FakeFS(existing: [:]),
                                       trash: FakeTrash(failing: [path]),
                                       running: FakeRunning(running: []),
                                       store: NamespacedStore(namespace: UninstallerEngine.moduleID,
                                                              backing: InMemoryKeyValueStore()))
        let result = await engine.trashPaths([path])

        XCTAssertEqual(result.failed, [path], "precondition: macOS refused the app")
        XCTAssertTrue(logged.contains { $0.hasPrefix("trash refused ") },
                      "the refusal line was not written, so an absence proves nothing: \(logged)")
        XCTAssertFalse(logged.contains { $0.contains(secret) },
                       "the log names the application: \(logged)")
    }
}
