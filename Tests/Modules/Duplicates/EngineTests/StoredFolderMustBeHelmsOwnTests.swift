import HelmRuntime
import XCTest
@testable import Module_Duplicates_Engine

private struct TestKey: SealKeyPort {
    let firstUse: Bool
    func key() -> SealKey? {
        SealKey(material: Data(repeating: 0x11, count: 32), firstUse: firstUse)
    }
}

/// A background scan starts from a folder nobody re-chose, so the folder has to
/// be the one Helm stored.
///
/// `module.duplicates.folder` is a plain string in `com.helm.app.plist`. Until
/// scans ran unattended it only ever changed through an open panel with the
/// person present; now it decides how far a reader reaches with nobody at the
/// desk, and any process running as this user can rewrite it. `ScanRoot` bounds
/// where it may point — this is the other question, whether Helm put it there.
///
/// **The fixture lives in the home directory on purpose.** `ScanRoot` refuses a
/// root outside it, which is the gate working; a fixture in `/var/folders` would
/// make every case below come back nil for the wrong reason and the test would
/// pass without ever reaching the seal.
final class StoredFolderMustBeHelmsOwnTests: XCTestCase {

    private var fixture: URL!
    private var store: NamespacedStore!

    override func setUpWithError() throws {
        fixture = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".helm-seal-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let payload = Data(repeating: 0x42, count: 1_200_000)
        try payload.write(to: fixture.appendingPathComponent("one.bin"))
        try payload.write(to: fixture.appendingPathComponent("two.bin"))
        store = NamespacedStore(namespace: "duplicates", backing: InMemoryKeyValueStore())
        store.set(fixture.path, for: "folder")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
    }

    private func engine(firstUse: Bool = false) -> DuplicatesEngine {
        DuplicatesEngine(store: store,
                         settings: SettingGuard(keys: TestKey(firstUse: firstUse)))
    }

    func testASealedFolderIsScanned() async throws {
        let sealed = SettingGuard(keys: TestKey(firstUse: false))
        store.set(sealed.seal(Data(fixture.path.utf8)) ?? "",
                  for: SettingGuard.macKey(for: "folder"))
        let answer = await engine().backgroundScan()
        let report = try XCTUnwrap(answer)
        XCTAssertEqual(report.count, 1, "one extra copy of one file")
    }

    /// The whole point: the value changed and the seal did not, because whoever
    /// wrote it does not have the key.
    func testAFolderSomethingElseWroteIsRefused() async {
        let sealed = SettingGuard(keys: TestKey(firstUse: false))
        store.set(sealed.seal(Data("/somewhere/else".utf8)) ?? "",
                  for: SettingGuard.macKey(for: "folder"))
        let report = await engine().backgroundScan()
        XCTAssertNil(report, "a folder Helm did not store must not be walked unattended")
    }

    /// A seal deleted along with nothing else is not evidence of an old install:
    /// whoever can write the folder can delete the MAC beside it.
    func testAMissingSealIsRefusedOnAnInstallationThatHasSealedBefore() async {
        let report = await engine().backgroundScan()
        XCTAssertNil(report)
    }

    /// And the one door left open, on the run that creates the key: the folder
    /// predates sealing, so it is accepted once — and sealed, so the next run
    /// does not have to trust anything.
    func testAFolderChosenBeforeSealingIsAdoptedAndSealed() async throws {
        let answer = await engine(firstUse: true).backgroundScan()
        let report = try XCTUnwrap(answer)
        XCTAssertEqual(report.count, 1)
        XCTAssertFalse(store.string(SettingGuard.macKey(for: "folder"), default: "").isEmpty,
                       "adopting without sealing leaves the same question open tomorrow")
    }
}
