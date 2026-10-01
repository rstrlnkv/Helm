import Foundation
import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// **Every refusal line the shared removal loop writes for this module, at the
/// inputs the first test did not feed in.** `TheLogDoesNotNameTheAppTests` fed
/// one bundle in `/Applications` and a one-word message. The loop writes three
/// kinds of line — out of scope, ancestor changed, macOS refused — and the
/// uninstaller hands it bundles in nested folders, and leftovers named by a
/// bundle id with no extension of their own (`~/Library/Containers/<id>`),
/// while macOS names a refused bundle by its *display name* in its own half of
/// the line.
///
/// Every case asserts that its line was written before asserting what the line
/// does not carry: the log is off in a test process, and an absence proves
/// nothing about a line that was never there.
final class TheLogDoesNotNameTheAppUnderOddInputsTests: XCTestCase {

    /// The part of the name the tests look for; long enough that `Redact.naming`
    /// does not skip it for being short, unique so another run's line cannot
    /// match.
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

    // MARK: - Out of scope

    /// `/Applications/Utilities` is on the gate's forbidden list, so a bundle
    /// there never reaches `trashItem` and is logged by the out-of-scope line.
    func testABundleInAForbiddenFolderIsRefusedWithoutItsName() async {
        let path = "/Applications/Utilities/\(secret).app"
        let result = await engine(trash: FakeTrash()).trashPaths([path])
        XCTAssertEqual(result.failures.map(\.reason), [.outOfScope], "precondition: the gate refused it")
        assertLogged("refused out-of-scope path: ", without: [secret])
    }

    // MARK: - Nested bundles, macOS refusing

    /// A bundle one folder down and one in the home's own Applications folder:
    /// the leaf is still the app's name.
    func testNestedBundlesAreRefusedWithoutTheirNames() async {
        let paths = ["/Applications/Setapp/\(secret).app", "/Users/x/Applications/\(secret).app"]
        let result = await engine(trash: FakeTrash(failing: paths)).trashPaths(paths)
        XCTAssertEqual(Set(result.failed), Set(paths), "precondition: macOS refused both")
        assertLogged("trash refused ", without: [secret])
    }

    /// macOS's own half of the line in Russian, quoting the bundle by its file
    /// name: `Redact.naming` has to find the name inside somebody else's
    /// sentence.
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
    /// it.» The redaction replaces the file's stem, which that sentence does not
    /// contain, so the display name stays in clear.
    func testARefusalQuotingTheDisplayNameDoesNotNameTheApp() async {
        let path = "/Applications/\(secret).app"
        let shown = "Hidden Title \(secret.suffix(6))"
        let said = "“\(shown)” couldn’t be moved to the trash because you don’t have "
            + "permission to access it."
        let result = await engine(trash: SayingTrash(failing: [path: said])).trashPaths([path])
        XCTAssertEqual(result.failed, [path], "precondition: macOS refused the app")
        assertLogged("trash refused ", without: [secret, shown])
    }

    /// **A name under four characters survives in macOS's half of the line.**
    /// `Redact.naming` skips it on purpose (replacing a short word everywhere
    /// rewrites the sentence), and `Arc.app` and `Zed.app` are real products.
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
        return .success
    }
}
