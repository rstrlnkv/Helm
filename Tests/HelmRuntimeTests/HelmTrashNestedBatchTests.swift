import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// A batch that contains a folder and something inside it.
///
/// Disk reaches this without trying: the advice list offers `~/Library/Caches`
/// while the ring, three levels down, offers `~/Library/Caches/com.acme.tool`,
/// and `toggleBasket` only dedupes by exact path. Both go into one basket and
/// one `trash` call.
///
/// Whichever goes first, both are gone afterwards — trashing a folder takes its
/// contents. But if the parent went first, the child's own `trashItem` fails
/// with `NSFileNoSuchFileError`, which `TrashFailure.reason` classifies as
/// `.systemRefused`, and the screen tells the person that macOS refused to move
/// a file that is already in their Trash. `UninstallerEngine.trashSync` has the
/// guard for exactly this ("already gone … is not a failure"); the shared loop
/// the other three modules were moved onto does not.
///
/// The order a batch arrives in is a hash seed's (`DiskEngine.trash` feeds this
/// `Array(Set(paths))`), and `HelmTrashBatchOutcomeTests` holds both orders to one
/// absolute answer.
final class HelmTrashNestedBatchTests: XCTestCase {

    private var roots: [URL] = []
    /// Names of the items that really went to the Trash. Unique, because
    /// `trashItem` is called without `resultingItemURL` and the name is all the
    /// cleanup has to go on — it must never be a name somebody else could own.
    private var trashedNames: [String] = []

    override func tearDownWithError() throws {
        let fm = FileManager.default
        for root in roots { try? fm.removeItem(at: root) }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let trash = (try? fm.url(for: .trashDirectory, in: .userDomainMask,
                                 appropriateFor: home, create: false))
            ?? home.appendingPathComponent(".Trash")
        for name in trashedNames { try? fm.removeItem(at: trash.appendingPathComponent(name)) }
        roots = []
        trashedNames = []
    }

    /// A folder holding one 300 KB file. Returns (parent, child).
    private func makeTree() throws -> (String, String) {
        let root = scratchDirectory("nested")
        let name = "helm-nested-folder-\(UUID().uuidString)"
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let childName = "helm-nested-file-\(UUID().uuidString).bin"
        let child = folder.appendingPathComponent(childName)
        try Data(repeating: 0x41, count: 300_000).write(to: child)
        roots.append(root)
        trashedNames.append(contentsOf: [name, childName])
        return (folder.path, child.path)
    }

    func testTheChildIsNotCalledARefusalWhenTheParentTookItFirst() throws {
        let (parent, child) = try makeTree()

        let result = HelmTrash.remove(allowed: [parent, child], module: "test")

        XCTAssertFalse(FileManager.default.fileExists(atPath: child),
                       "precondition: the child went with its parent")
        XCTAssertEqual(result.refused, [],
                       "a path that is gone is not something the person can act on")
        XCTAssertEqual(Set(result.removed), [parent, child])
    }
}
