import XCTest
import HelmTestSupport
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// `ringLayout(forFocusAt:)` resolves a path to a node through `DiskFocus.chain`
/// (it used to carry a search of its own). The root, a child, a grandchild and a
/// namesake ("/r/b" against "/r/bc") must each land on their own folder, and a
/// path the tree does not hold must draw nothing.
@MainActor
final class TheRingLayoutForAFocusPathFindsTheRightFolderTests: XCTestCase {

    private func model() -> DiskViewModel {
        let dvm = DiskViewModel(work: HeldWork(),
                                store: ScanStore(directory: scratchDirectory("disk-ringpath")))
        dvm.result = ScanResult(
            root: folder("/r", bytes: 900, children: [
                folder("/r/b", bytes: 500, children: [folder("/r/b/c", bytes: 300, children: [
                    folder("/r/b/c/leaf1", bytes: 200), folder("/r/b/c/leaf2", bytes: 100)])]),
                folder("/r/bc", bytes: 400, children: [folder("/r/bc/e", bytes: 400)]),
            ]),
            freeBytes: 0, filesScanned: 5, seconds: 1)
        return dvm
    }

    private func innermost(_ dvm: DiskViewModel, _ path: String) -> [String] {
        dvm.ringLayout(forFocusAt: path).filter { $0.ring == 0 }.map(\.path)
    }

    func testTheRootAChildAndAGrandchildEachLandOnTheirOwnFolder() {
        let dvm = model()
        XCTAssertEqual(Set(innermost(dvm, "/r")), ["/r/b", "/r/bc"])
        XCTAssertEqual(innermost(dvm, "/r/b"), ["/r/b/c"])
        XCTAssertEqual(Set(innermost(dvm, "/r/b/c")), ["/r/b/c/leaf1", "/r/b/c/leaf2"])
    }

    func testANamesakeIsNotTheFolderItSharesAPrefixWith() {
        XCTAssertEqual(innermost(model(), "/r/bc"), ["/r/bc/e"])
    }

    func testAPathTheTreeDoesNotHoldDrawsNothing() {
        let dvm = model()
        XCTAssertTrue(dvm.ringLayout(forFocusAt: "/r/zz").isEmpty)
        XCTAssertTrue(dvm.ringLayout(forFocusAt: "/r/b/zz").isEmpty)
    }
}
