import Foundation
import XCTest
import HelmTestSupport
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
    /// Names of everything this test may have moved to the Trash.
    ///
    /// **The removal here is real**: `HelmTrash.remove` calls
    /// `FileManager.trashItem`, so a file the engine takes leaves the temporary
    /// home below and lands in `~/.Trash`, where deleting the temp directory
    /// cannot reach it. Six removals a run, kept for good, on the machine of
    /// whoever runs `swift test`.
    ///
    /// `trashItem` is called with `resultingItemURL: nil`, so the name is all
    /// the cleanup has to go on — which is why every name `write` makes carries
    /// a UUID. A cleanup that removed `~/.Trash/cache.bin` would be deleting
    /// somebody's file. `HelmTrashNestedBatchTests` is where this pattern is
    /// written down; this file is one of the eight that did not follow it.
    private var trashedNames: [String] = []

    override func setUpWithError() throws {
        // A temporary directory the engine is told is home. `RemovableScope`
        // refuses everything outside one, and a test that asked for an
        // exemption from that gate would be testing a different program.
        home = scratchDirectory("leftovers")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Application Support"),
            withIntermediateDirectories: true)
        engine = LeftoversEngine(home: home)
    }

    override func tearDownWithError() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: home)
        let userHome = URL(fileURLWithPath: NSHomeDirectory())
        let trash = (try? fm.url(for: .trashDirectory, in: .userDomainMask,
                                 appropriateFor: userHome, create: false))
            ?? userHome.appendingPathComponent(".Trash")
        for name in trashedNames { try? fm.removeItem(at: trash.appendingPathComponent(name)) }
        trashedNames = []
    }

    /// A unique leaf under `relative`, so the Trash cleanup above can name what
    /// it removes without ever naming somebody else's file.
    @discardableResult
    /// Not the shared `write` on its own: these files are really trashed, so
    /// the leaf carries a UUID nobody else could own and goes on the list the
    /// teardown reclaims by name.
    private func write(_ relative: String, named leaf: String, bytes: Int) throws -> String {
        let name = "\(leaf)-\(UUID().uuidString)"
        trashedNames.append(name)
        return try write("\(relative)/\(name)", in: home, bytes: bytes).path
    }

    /// A folder with a unique name, for the case that trashes the folder itself.
    private func folder(_ relative: String, named leaf: String) throws -> URL {
        let name = "\(leaf)-\(UUID().uuidString)"
        let url = home.appendingPathComponent(relative).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        trashedNames.append(name)
        return url
    }

    // MARK: - The gate

    /// The engine has the last word. A path outside the scope is refused here
    /// even though the view model would never offer it.
    func testAPathOutsideTheScopeIsRefusedAndNotSilentlyDropped() async throws {
        let inside = try write("Library/Application Support/Ghost", named: "cache", bytes: 4_000)
        let outside = home.appendingPathComponent("Documents/thesis.txt").path

        let result = await engine.trash([inside, outside])

        XCTAssertEqual(result.removed, [inside])
        XCTAssertEqual(result.failed, [outside],
                       "a refused path reached neither list and the count then lied")
        // The reason is a reason now that this is the shared result, so the
        // refusal can be asked *why* rather than only *whether*.
        XCTAssertEqual(result.refused.map(\.reason), [.outOfScope])
        XCTAssertFalse(FileManager.default.fileExists(atPath: inside))
    }

    /// The count and the list have to agree: every path handed in comes back
    /// either removed or refused, exactly once.
    func testEveryPathComesBackExactlyOnce() async throws {
        let a = try write("Library/Caches/Ghost", named: "one", bytes: 1_000)
        let b = try write("Library/Caches/Ghost", named: "two", bytes: 1_000)
        let outside = home.appendingPathComponent("thesis.txt").path

        let result = await engine.trash([a, b, outside, a])   // one repeated

        XCTAssertEqual(Set(result.removed + result.failed), [a, b, outside])
        XCTAssertEqual(result.removed.count + result.failed.count, 3, "the repeat was counted twice")
    }

    // MARK: - What it says was freed

    func testFreedCountsOnlyWhatWasActuallyRemoved() async throws {
        let removed = try write("Library/Application Support/Ghost", named: "big", bytes: 500_000)
        let outside = home.appendingPathComponent("Documents/keep.bin").path

        let result = await engine.trash([removed, outside])

        XCTAssertGreaterThanOrEqual(result.freedBytes, 500_000)
        XCTAssertLessThan(result.freedBytes, 600_000, "the refused path was counted as freed")
    }

    /// The bundles this module removes — plug-ins, extensions, agents — are
    /// folders. A folder that reports its directory entry rather than its
    /// contents reports zero, which is the one number this screen exists for.
    func testAFolderFreesWhatIsInsideIt() async throws {
        // The folder is what goes, so it is the one that needs the unique
        // name; what is inside it travels with it.
        let ghost = try folder("Library/Application Support", named: "Ghost")
        try Data(repeating: 0x41, count: 700_000)
            .write(to: ghost.appendingPathComponent("payload.bin"))
        try Data(repeating: 0x41, count: 1_000)
            .write(to: ghost.appendingPathComponent("Info.plist"))
        let bundle = ghost.path

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
        XCTAssertEqual(result.failed, [missing])
        XCTAssertEqual(result.freedBytes, 0)
    }
}
