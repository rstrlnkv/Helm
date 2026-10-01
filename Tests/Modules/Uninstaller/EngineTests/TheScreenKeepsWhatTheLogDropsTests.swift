import Foundation
import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// **The refusal line stopped carrying macOS's sentence; the failure sheet must
/// not have stopped with it.** The sentence is evidence a person reads under the
/// classified reason, and it reaches the sheet only through the engine's own
/// record of what the trash port said. A fix to the log that also emptied that
/// record would pass every test that reads the log alone.
final class TheScreenKeepsWhatTheLogDropsTests: XCTestCase {

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

    private func engine(trash: TrashPort) -> UninstallerEngine {
        UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"), apps: FakeApps(),
                          fs: FakeFS(existing: [:]), trash: trash,
                          running: FakeRunning(running: []),
                          extensions: NoSystemExtensions(),
                          store: NamespacedStore(namespace: UninstallerEngine.moduleID,
                                                 backing: InMemoryKeyValueStore()))
    }

    /// One bundle and one leftover named by its id, both refused with a sentence
    /// that quotes the display name: the sheet gets each sentence verbatim, the
    /// log gets the code and the reason and neither name.
    func testTheSentenceReachesTheSheetAndNotTheLog() async {
        let shown = "Hidden Title \(secret.suffix(6))"
        let bundle = "/Applications/\(secret).app"
        let leftover = "/Users/x/Library/Containers/com.acme.\(secret)"
        let said = [
            bundle: "“\(shown)” couldn’t be moved to the trash because you don’t have "
                + "permission to access it.",
            leftover: "“com.acme.\(secret)” couldn’t be moved to the trash because you "
                + "don’t have permission to access it.",
        ]
        let result = await engine(trash: Refusing(said: said)).trashPaths([bundle, leftover])

        XCTAssertEqual(Set(result.failed), [bundle, leftover], "precondition: macOS refused both")
        let byPath = Dictionary(uniqueKeysWithValues: result.failures.map { ($0.path, $0) })
        XCTAssertEqual(byPath[bundle]?.message, said[bundle], "the sheet lost macOS's sentence")
        XCTAssertEqual(byPath[leftover]?.message, said[leftover], "the sheet lost macOS's sentence")
        XCTAssertEqual(byPath[bundle]?.reason, .noPermission)
        XCTAssertEqual(byPath[leftover]?.reason, .needsFullDiskAccess)

        let lines = logged.filter { $0.hasPrefix("trash refused ") }
        XCTAssertEqual(lines.count, 2, "precondition: one refusal line per path: \(logged)")
        XCTAssertTrue(lines.contains { $0.hasSuffix(": NSCocoaErrorDomain 513, noPermission") },
                      "the bundle's verdict is not in the log: \(lines)")
        XCTAssertTrue(lines.contains { $0.hasSuffix(": NSCocoaErrorDomain 513, needsFullDiskAccess") },
                      "the leftover's verdict is not in the log: \(lines)")
        for name in [secret, shown, "couldn’t be moved"] {
            XCTAssertFalse(logged.contains { $0.contains(name) }, "the log carries «\(name)»: \(logged)")
        }
    }
}

/// macOS refusing every path it has a sentence for, with that sentence.
private struct Refusing: TrashPort {
    let said: [String: String]
    func trashItem(_ url: URL) -> TrashOutcome {
        guard let sentence = said[url.path] else { return .success }
        return TrashOutcome(succeeded: false, errorCode: 513, message: sentence)
    }
}
