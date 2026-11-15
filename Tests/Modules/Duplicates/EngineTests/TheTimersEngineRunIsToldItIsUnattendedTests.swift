import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// `TheTimersWalkStaysOutOfTheLibraryTests` drives the scanner, so it is green
/// whatever the engine tells the scanner. This one goes through `backgroundScan`
/// and asks what the engine asked for: a walk nobody watches stops at the
/// Library of its home, and a flipped flag at that call is the defect.
///
/// The fixture is in the real home because `ScanRoot` refuses a root outside
/// it; the scanner is handed the fixture as its home, so its `Library` is a
/// scratch one and the owner's own is never read.
final class TheTimersEngineRunIsToldItIsUnattendedTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".helm-unattended-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        let payload = Data(repeating: 0x43, count: 1_200_000)
        try payload.write(to: home.appendingPathComponent("holiday.jpg"))
        try payload.write(to: home.appendingPathComponent("Library/Caches/holiday.jpg"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testTheBackgroundScanDoesNotEnterTheLibrary() async throws {
        let store = NamespacedStore(namespace: "duplicates", backing: InMemoryKeyValueStore())
        store.set(home.path, for: "folder")
        let fixture = home.path
        let engine = DuplicatesEngine(
            store: store, settings: SettingGuard(keys: SealKeyProbe(firstUse: true)), trashing: neverTrashes,
            verifying: { { _, _ in fatalError("nothing is verified by a scan") } },
            scanning: { DuplicateScanner(unattended: $0, home: fixture) })
        let answer = await engine.backgroundScan()
        let report = try XCTUnwrap(answer)
        XCTAssertEqual(report.count, 0, "the copy inside the Library was reached: \(report.items)")
    }
}
