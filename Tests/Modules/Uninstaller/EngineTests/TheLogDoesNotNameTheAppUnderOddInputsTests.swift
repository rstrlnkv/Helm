import Foundation
import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// **The refusal lines the shared removal loop writes for this module, at the
/// inputs `TheLogDoesNotNameTheAppTests` did not feed in.** That class feeds one
/// bundle in `/Applications`, a bundle in a forbidden folder (the out-of-scope
/// line) and nested bundles. The loop writes three kinds of line — out of scope,
/// ancestor changed, macOS refused — and this class feeds the last two.
/// Ancestor changed: a leftover whose parent was swapped. macOS refused:
/// leftovers named by a bundle id, with an extension or with none of their own
/// (`~/Library/Containers/<id>`), and a refusal whose sentence names the bundle
/// by its *display name*, in Russian, or by a name of three letters: the line
/// leaves that sentence out.
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
        // The sentence is not logged any more (it quotes names the redaction cannot
        // find); the code and Helm's own classification are what the line carries.
        XCTAssertTrue(logged.contains { $0.contains("NSCocoaErrorDomain 513, noPermission") },
                      "the system's half of the line was not logged: \(logged)")
        XCTAssertFalse(logged.contains { $0.contains("Корзину") },
                       "macOS's sentence reached the log: \(logged)")
        assertLogged("trash refused ", without: [secret])
    }

    // MARK: - Leftovers named by a bundle id

    /// **The common leftover has no extension of its own**, so the bundle id's
    /// last dot is read as one: `Containers/com.acme.SecretTool` is a stem of
    /// `com.acme` and an "extension" of `SecretTool`, and the line keeps the
    /// part of the id that names the product. `Caches/<id>`,
    /// `Application Support/<id>`, `HTTPStorages/<id>`, `WebKit/<id>` and the
    /// group container `<team>.<id>` are the same shape (`LeftoverMatcher`).
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
    /// is tagged. This passes today and is what the one above should read like.
    func testALeftoverWithAnExtensionIsRefusedWithoutTheID() async {
        let id = "com.acme.\(secret)"
        let path = "/Users/x/Library/Preferences/\(id).plist"
        let result = await engine(trash: FakeTrash(failing: [path])).trashPaths([path])
        XCTAssertEqual(result.failed, [path], "precondition: macOS refused it")
        assertLogged("trash refused ", without: [secret, "com.acme"])
    }

    // MARK: - The name macOS uses is not the file's

    /// **macOS names a refused bundle by its display name**, measured on this
    /// Mac: `trashItem` on a bundle `SecretTool.app` whose `InfoPlist.strings`
    /// says `CFBundleDisplayName = "Hidden Title"` answered «“Hidden Title”
    /// couldn’t be moved to the trash because you don’t have permission to access
    /// it.» Redaction replaces the file's stem, which that sentence does not
    /// contain, so the line carries the error's domain and code instead.
    func testARefusalQuotingTheDisplayNameDoesNotNameTheApp() async {
        let path = "/Applications/\(secret).app"
        let shown = "Hidden Title \(secret.suffix(6))"
        let said = "“\(shown)” couldn’t be moved to the trash because you don’t have "
            + "permission to access it."
        let result = await engine(trash: SayingTrash(failing: [path: said])).trashPaths([path])
        XCTAssertEqual(result.failed, [path], "precondition: macOS refused the app")
        assertLogged("trash refused ", without: [secret, shown])
    }

    /// **A three-letter name reaches the log in no form.** `Arc.app` and
    /// `Zed.app` are real products; the refusal line carries the code and Helm's
    /// classification, never the system's sentence, so the length of the name
    /// decides nothing.
    func testAThreeLetterAppIsRefusedWithoutItsName() async {
        let path = "/Applications/Qzx.app"
        let said = "“Qzx” couldn’t be moved to the trash because you don’t have "
            + "permission to access it."
        let result = await engine(trash: SayingTrash(failing: [path: said])).trashPaths([path])
        XCTAssertEqual(result.failed, [path], "precondition: macOS refused the app")
        assertLogged("trash refused ", without: ["Qzx"])
    }

    // MARK: - Ancestor changed

    /// The third line the loop writes: a parent swapped between the gate and the
    /// move. Driven on real directories, because the ancestry read is `stat` on
    /// the parent: the first path's move renames the second path's parent away
    /// and puts a fresh folder of the same name in its place.
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
