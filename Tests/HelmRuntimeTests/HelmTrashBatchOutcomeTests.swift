import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// Either order of a nested batch, asserted absolutely.
///
/// Comparing a parent-first run with a child-first run proves nothing: `remove`
/// sorts the batch before it starts, so the two agree by construction, and two
/// wrongs of equal size agree too.
///
/// So the assertion that a person actually cares about is absolute, not
/// comparative: whichever order the basket arrives in, both paths are gone,
/// nothing is reported as a refusal, and the bytes are counted once.
final class HelmTrashBatchOutcomeTests: XCTestCase {

    private var roots: [URL] = []
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
        let root = scratchDirectory("batch")
        let name = "helm-batch-folder-\(UUID().uuidString)"
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let childName = "helm-batch-file-\(UUID().uuidString).bin"
        try Data(repeating: 0x41, count: 300_000)
            .write(to: folder.appendingPathComponent(childName))
        roots.append(root)
        trashedNames.append(contentsOf: [name, childName])
        return (folder.path, folder.appendingPathComponent(childName).path)
    }

    func testEitherOrderRemovesBothPathsRefusesNothingAndCountsTheBytesOnce() throws {
        for parentFirst in [true, false] {
            let (parent, child) = try makeTree()
            let batch = parentFirst ? [parent, child] : [child, parent]

            let result = HelmTrash.remove(allowed: batch, module: "test")
            let order = parentFirst ? "parent first" : "child first"

            XCTAssertEqual(Set(result.removed), [parent, child],
                           "\(order): the batch reports \(result.removed.count) of 2 removed")
            XCTAssertEqual(result.refused, [],
                           "\(order): a path this batch took is not something the person "
                           + "can act on — \(result.refused)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: parent), "\(order)")
            XCTAssertGreaterThanOrEqual(result.freedBytes, 300_000, "\(order)")
            XCTAssertLessThan(result.freedBytes, 600_000,
                              "\(order): the 300 KB inside the folder was counted twice — "
                              + "once for the folder and once for the file basketed with it")
        }
    }

    /// The other half of the rule, which the shared loop states in a comment and
    /// which nothing pins: a path that was *already* gone before the batch
    /// started stays a refusal. The list on screen is minutes old, and "it was
    /// not there" is the one thing worth telling the person about it.
    func testAPathGoneBeforeTheBatchIsStillARefusalEvenBesideARemovedFolder() throws {
        let (parent, _) = try makeTree()
        // Not under `parent`: a sibling that vanished between the scan and now.
        let vanished = URL(fileURLWithPath: parent).deletingLastPathComponent()
            .appendingPathComponent("never-existed.bin").path

        let result = HelmTrash.remove(allowed: [parent, vanished], module: "test")

        XCTAssertEqual(result.removed, [parent])
        XCTAssertEqual(result.refused.map(\.path), [vanished],
                       "a stale row was reported as though the batch had taken it")
    }
}
