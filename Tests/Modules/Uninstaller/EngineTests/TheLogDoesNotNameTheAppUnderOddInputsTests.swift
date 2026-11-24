import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// The refusal lines the shared removal loop writes for this module name no
/// app, at the inputs `TheLogDoesNotNameTheAppTests` does not feed: a leftover
/// whose parent was swapped, leftovers named by a bundle id with or without an
/// extension, and macOS sentences naming the bundle by display name, in
/// Russian, or by three letters. The line leaves the sentence out.
///
/// Every case asserts that its line was written before asserting what the line
/// does not carry: the log is off in a test process, and an absence proves
/// nothing about a line that was never there.
final class TheLogDoesNotNameTheAppUnderOddInputsTests: XCTestCase {

    /// The part of the name the tests look for; unique so another run's line
    /// cannot match.
    private let secret = "SecretTool\(UUID().uuidString.prefix(6))"

    override func setUp() {
        super.setUp()
        tailTheLog()
    }

    private var logged: [String] {
        loggedLines(UninstallerEngine.moduleID)
    }

    private func engine(home: String = "/Users/x", trash: TrashPort) -> UninstallerEngine {
        UninstallerEngine(home: URL(fileURLWithPath: home), apps: FakeApps(),
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

    // MARK: - macOS refusing

    /// macOS's own half of the line in Russian, quoting the bundle by its file
    /// name: the sentence is not logged, so the name inside it cannot reach the
    /// log.
    func testARussianRefusalQuotingTheNameIsRedacted() async {
        let path = "/Applications/\(secret).app"
        let said = "Не удалось переместить объект «\(secret)» в Корзину, "
            + "так как у Вас нет разрешения на доступ к нему."
        let result = await engine(trash: SayingTrash(failing: [path: said])).trashPaths([path])
        XCTAssertEqual(result.failed, [path], "precondition: macOS refused the app")
        // The sentence is not logged (it quotes names the redaction cannot find);
        // the code and Helm's own classification are what the line carries.
        XCTAssertTrue(logged.contains { $0.contains("NSCocoaErrorDomain 513, noPermission") },
                      "the system's half of the line was not logged: \(logged)")
        XCTAssertFalse(logged.contains { $0.contains("Корзину") },
                       "macOS's sentence reached the log: \(logged)")
        assertLogged("trash refused ", without: [secret])
    }

    // MARK: - Leftovers named by a bundle id

    /// The common leftover has no extension of its own, so the id's last dot
    /// would be read as one (`com.acme` + `SecretTool`) and the product's name
    /// kept. `Caches/<id>`, `Application Support/<id>` and the group container
    /// `<team>.<id>` are the same shape (`LeftoverMatcher`).
    func testALeftoverNamedByABundleIDIsRefusedWithoutTheProductsName() async {
        let id = "com.acme.\(secret)"
        let paths = ["/Users/x/Library/Containers/\(id)",
                     "/Users/x/Library/Caches/\(id)",
                     "/Users/x/Library/Group Containers/ABCDE12345.\(id)"]
        let said = "“\(id)” couldn’t be moved to the trash because you don’t have "
            + "permission to access it."
        let result = await engine(trash: SayingTrash(failing: Dictionary(uniqueKeysWithValues:
            paths.map { ($0, said) }))).trashPaths(paths)
        XCTAssertEqual(Set(result.failed), Set(paths), "precondition: macOS refused all three")
        assertLogged("trash refused ", without: [secret])
    }

    /// A leftover with an extension, for contrast: the stem is the whole id and
    /// is tagged.
    func testALeftoverWithAnExtensionIsRefusedWithoutTheID() async {
        let id = "com.acme.\(secret)"
        let path = "/Users/x/Library/Preferences/\(id).plist"
        let result = await engine(trash: FakeTrash(failing: [path])).trashPaths([path])
        XCTAssertEqual(result.failed, [path], "precondition: macOS refused it")
        assertLogged("trash refused ", without: [secret, "com.acme"])
    }

    // MARK: - The name macOS uses is not the file's

    /// macOS names a refused bundle by its display name, which redaction of the
    /// file's stem cannot find, so the line carries the error's domain and code.
    func testARefusalQuotingTheDisplayNameDoesNotNameTheApp() async {
        let path = "/Applications/\(secret).app"
        let shown = "Hidden Title \(secret.suffix(6))"
        let said = "“\(shown)” couldn’t be moved to the trash because you don’t have "
            + "permission to access it."
        let result = await engine(trash: SayingTrash(failing: [path: said])).trashPaths([path])
        XCTAssertEqual(result.failed, [path], "precondition: macOS refused the app")
        assertLogged("trash refused ", without: [secret, shown])
    }

    /// A three-letter name (`Arc.app`) reaches the log in no form: the line never
    /// carries the system's sentence, so the name's length decides nothing.
    func testAThreeLetterAppIsRefusedWithoutItsName() async {
        let path = "/Applications/Qzx.app"
        let said = "“Qzx” couldn’t be moved to the trash because you don’t have "
            + "permission to access it."
        let result = await engine(trash: SayingTrash(failing: [path: said])).trashPaths([path])
        XCTAssertEqual(result.failed, [path], "precondition: macOS refused the app")
        assertLogged("trash refused ", without: ["Qzx"])
    }

    // MARK: - Ancestor changed

    /// A parent swapped between the gate and the move. Real directories, since
    /// the ancestry read is `stat`: the first move renames the second path's
    /// parent away and puts a fresh folder in its place.
    func testALeftoverWhoseParentWasSwappedIsRefusedWithoutItsName() async throws {
        let root = scratchDirectory("uninstaller-ancestry")
        let home = (root.path as NSString).resolvingSymlinksInPath
        let first = home + "/Library/Caches/a"
        let parent = home + "/Library/Application Support"
        let second = parent + "/\(secret)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: first, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: second, withIntermediateDirectories: true)
        let swapper = SwappingTrash(on: first) {
            try? fm.moveItem(atPath: parent, toPath: home + "/Library/moved")
            try? fm.createDirectory(atPath: second, withIntermediateDirectories: true)
        }
        let result = await engine(home: home, trash: swapper).trashPaths([first, second])
        XCTAssertEqual(result.failures.map(\.reason), [.changedSinceScan],
                       "precondition: the second path's parent changed under the batch")
        assertLogged("refused: ancestor changed since the gate: ", without: [secret])
    }
}

/// macOS refusing named paths with the sentence it would say about each.
private struct SayingTrash: TrashPort {
    let failing: [String: String]
    func trashItem(_ url: URL) -> TrashOutcome {
        guard let said = failing[url.path] else { return .success }
        return TrashOutcome(succeeded: false, errorCode: 513, message: said)
    }
}

/// Succeeds on every path, and runs `swap` when it is handed `on`.
private final class SwappingTrash: TrashPort, @unchecked Sendable {
    private let on: String
    private let swap: () -> Void
    init(on: String, swap: @escaping () -> Void) { self.on = on; self.swap = swap }
    func trashItem(_ url: URL) -> TrashOutcome {
        if url.path == on { swap() }
        // Gone from its place, as a real move leaves it: `HelmTrash.remove` asks.
        try? FileManager.default.removeItem(at: url)
        return .success
    }
}
