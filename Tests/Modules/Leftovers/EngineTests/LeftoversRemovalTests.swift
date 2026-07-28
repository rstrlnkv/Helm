import Foundation
import XCTest
@testable import HelmRuntime
@testable import Module_Leftovers_Engine

/// Removal, through the engine, over real files.
///
/// This path had no test at all. The port that exists to make it fakeable
/// (`LeftoversFilePort.trash`) is stubbed to `.success` by both fakes and
/// driven by nothing, so the seam bought a fake success and no coverage of the
/// thing that matters: what the engine refuses, what it counts, and what it
/// says happened.
///
/// Written before the loop moves onto `HelmTrash`, so the move has something to
/// be measured against rather than a promise that it is equivalent.
final class LeftoversRemovalTests: XCTestCase {

    private var home: URL!
    private var engine: LeftoversEngine!

    override func setUpWithError() throws {
        // A temporary directory the engine is told is home. `RemovableScope`
        // refuses everything outside one, and a test that asked for an
        // exemption from that gate would be testing a different program.
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-leftovers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Application Support"),
            withIntermediateDirectories: true)
        engine = LeftoversEngine(home: home)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    private func write(_ relative: String, bytes: Int) throws -> String {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    // MARK: - The gate

    /// The engine has the last word. A path outside the scope is refused here
    /// even though the view model would never offer it.
    func testAPathOutsideTheScopeIsRefusedAndNotSilentlyDropped() async throws {
        let inside = try write("Library/Application Support/Ghost/cache.bin", bytes: 4_000)
        let outside = home.appendingPathComponent("Documents/thesis.txt").path

        let result = await engine.trash([inside, outside])

        XCTAssertEqual(result.removed, [inside])
        XCTAssertEqual(result.failed.map(\.path), [outside],
                       "a refused path reached neither list and the count then lied")
        XCTAssertFalse(FileManager.default.fileExists(atPath: inside))
    }

    /// The count and the list have to agree: every path handed in comes back
    /// either removed or refused, exactly once.
    func testEveryPathComesBackExactlyOnce() async throws {
        let a = try write("Library/Caches/Ghost/one.bin", bytes: 1_000)
        let b = try write("Library/Caches/Ghost/two.bin", bytes: 1_000)
        let outside = home.appendingPathComponent("thesis.txt").path

        let result = await engine.trash([a, b, outside, a])   // one repeated

        XCTAssertEqual(Set(result.removed + result.failed.map(\.path)), [a, b, outside])
        XCTAssertEqual(result.removed.count + result.failed.count, 3, "the repeat was counted twice")
    }

    // MARK: - What it says was freed

    func testFreedCountsOnlyWhatWasActuallyRemoved() async throws {
        let removed = try write("Library/Application Support/Ghost/big.bin", bytes: 500_000)
        let outside = home.appendingPathComponent("Documents/keep.bin").path

        let result = await engine.trash([removed, outside])

        XCTAssertGreaterThanOrEqual(result.freedBytes, 500_000)
        XCTAssertLessThan(result.freedBytes, 600_000, "the refused path was counted as freed")
    }

    /// The bundles this module removes — plug-ins, extensions, agents — are
    /// folders. A folder that reports its directory entry rather than its
    /// contents reports zero, which is the one number this screen exists for.
    func testAFolderFreesWhatIsInsideIt() async throws {
        try write("Library/Application Support/Ghost/Contents/payload.bin", bytes: 700_000)
        try write("Library/Application Support/Ghost/Contents/Info.plist", bytes: 1_000)
        let bundle = home.appendingPathComponent("Library/Application Support/Ghost").path

        let result = await engine.trash([bundle])

        XCTAssertEqual(result.removed, [bundle])
        XCTAssertGreaterThan(result.freedBytes, 700_000)
    }

    // MARK: - Nothing at all

    func testRemovingNothingIsNotAnError() async throws {
        let result = await engine.trash([])
        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertEqual(result.freedBytes, 0)
    }

    /// A path that is gone by the time the removal runs — the scan is minutes
    /// old and the person may have tidied it themselves.
    func testAPathThatIsAlreadyGoneIsReportedAndNotCounted() async throws {
        let missing = home.appendingPathComponent("Library/Caches/Ghost/vanished.bin").path

        let result = await engine.trash([missing])

        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.failed.map(\.path), [missing])
        XCTAssertEqual(result.freedBytes, 0)
    }
}
