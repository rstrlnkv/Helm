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

    /// The part of the name the tests below look for; long enough that
    /// `Redact.naming` does not skip it for being short, unique so another
    /// run's line cannot match.
    private let secretTool = "SecretTool\(UUID().uuidString.prefix(6))"

    private func engine(trash: TrashPort) -> UninstallerEngine {
        UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"), apps: FakeApps(),
                          fs: FakeFS(existing: [:]), trash: trash,
                          running: FakeRunning(running: []),
                          extensions: NoSystemExtensions(),
                          store: NamespacedStore(namespace: UninstallerEngine.moduleID,
                                                 backing: InMemoryKeyValueStore()))
    }

    private func assertLogged(_ prefix: String, without names: [String],
                              file: StaticString = #filePath, line: UInt = #line) {
        let lines = logged
        XCTAssertTrue(lines.contains { $0.hasPrefix(prefix) },
                      "no «\(prefix)» line was written, so an absence proves nothing: \(lines)",
                      file: file, line: line)
        for name in names {
            XCTAssertFalse(lines.contains { $0.contains(name) },
                           "the log names «\(name)»: \(lines)", file: file, line: line)
        }
    }

    // MARK: - Out of scope

    /// `/Applications/Utilities` is on the gate's forbidden list, so a bundle
    /// there never reaches `trashItem` and is logged by the out-of-scope line.
    func testABundleInAForbiddenFolderIsRefusedWithoutItsName() async {
        let path = "/Applications/Utilities/\(secretTool).app"
        let result = await engine(trash: FakeTrash()).trashPaths([path])
        XCTAssertEqual(result.failures.map(\.reason), [.outOfScope], "precondition: the gate refused it")
        assertLogged("refused out-of-scope path: ", without: [secretTool])
    }

    // MARK: - Nested bundles, macOS refusing

    /// A bundle one folder down and one in the home's own Applications folder:
    /// the leaf is still the app's name.
    func testNestedBundlesAreRefusedWithoutTheirNames() async {
        let paths = ["/Applications/Setapp/\(secretTool).app", "/Users/x/Applications/\(secretTool).app"]
        let result = await engine(trash: FakeTrash(failing: paths)).trashPaths(paths)
        XCTAssertEqual(Set(result.failed), Set(paths), "precondition: macOS refused both")
        assertLogged("trash refused ", without: [secretTool])
    }
}
