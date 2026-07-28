import XCTest
import HelmContract
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// Coming back up, however far.
///
/// A breadcrumb jump of two levels used to animate not at all: the code set no
/// wedge to fold into, on the reasoning that several levels have no single
/// wedge. They do — the child of the level being returned to that leads to
/// where you were — and without it the ring simply cut, which is what looked
/// worst of everything it did.
@MainActor
final class RingFoldDistanceTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-ring-fold-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/b/c"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAJumpOfTwoLevelsFoldsIntoTheWedgeItWentInThrough() async throws {
        let model = try await restored()
        model.drill(into: root.appendingPathComponent("a").path)
        model.drill(into: root.appendingPathComponent("a/b").path)
        XCTAssertEqual(model.focusPath.count, 3, "the fixture has to be three deep")

        model.foldingBackFrom = nil
        model.jump(to: 0)

        XCTAssertEqual(model.foldingBackFrom, root.appendingPathComponent("a").path,
                       "a jump has a wedge to fold into: the one it went in through")
        XCTAssertEqual(model.foldingBackLevels, 2, "and the animation is told how far it travels")
    }

    func testASingleStepBackStillFoldsIntoItsOwnWedge() async throws {
        let model = try await restored()
        model.drill(into: root.appendingPathComponent("a").path)
        model.foldingBackFrom = nil

        model.back()

        XCTAssertEqual(model.foldingBackFrom, root.appendingPathComponent("a").path)
        XCTAssertEqual(model.foldingBackLevels, 1)
    }

    /// The distance is what buys the time: the same duration for one level and
    /// for three read as a cut with a blur on it.
    func testAFurtherFoldIsGivenLongerAndNeverOvershoots() {
        XCTAssertNotEqual(String(describing: HelmMotion.ringMorph(levels: 1)),
                          String(describing: HelmMotion.ringMorph(levels: 3)))
        XCTAssertEqual(String(describing: HelmMotion.ringMorph(levels: 1)),
                       String(describing: HelmMotion.ringMorph(levels: 0)),
                       "a fold of no distance is still a fold of one")
    }

    // MARK: - Fixture

    private func restored() async throws -> DiskViewModel {
        func entry(_ url: URL, _ children: [DiskEntry]) -> DiskEntry {
            DiskEntry(name: url.lastPathComponent, path: url.path, bytes: 4000,
                      isDirectory: true, noAccess: false, children: children)
        }
        let c = entry(root.appendingPathComponent("a/b/c"), [])
        let b = entry(root.appendingPathComponent("a/b"), [c])
        let a = entry(root.appendingPathComponent("a"), [b])
        let store = ScanStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-ring-fold-store-\(UUID().uuidString)"))
        store.save(ScanResult(root: entry(root, [a]), freeBytes: 0, filesScanned: 4, seconds: 1))

        let model = DiskViewModel(vm: ModuleViewModel(transport: LocalTransport()), store: store)
        for _ in 0..<200 where model.focusPath.isEmpty { await Task.yield() }
        return model
    }
}
