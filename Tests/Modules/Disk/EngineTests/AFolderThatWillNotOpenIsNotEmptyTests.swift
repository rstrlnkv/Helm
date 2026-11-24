import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine

/// A directory the walk could not open weighs nothing and says nothing about
/// why — unless it is flagged.
///
/// The row that says «No access» is the module's whole answer to a missing
/// permission, so the classification is held end to end through a real walk,
/// not through `markNoAccess` called by hand. A TCC refusal answers `EPERM`; a
/// failing disk (`EIO`, `ETIMEDOUT`) or a directory replaced by a file under the
/// walk (`ENOTDIR`) is not emptiness either, and read as an empty folder it
/// would draw a false zero on a map of where the space went.
final class AFolderThatWillNotOpenIsNotEmptyTests: XCTestCase {

    /// The permission case, produced rather than described: a real directory at
    /// mode 000, opened by the real walk.
    ///
    /// The mode is put back in a teardown registered after `scratchDirectory`'s,
    /// so it runs first: a 000 directory cannot be recursed into and removed.
    func testADirectoryWithNoPermissionsIsFlaggedRatherThanCountedAsEmpty() throws {
        let root = scratchDirectory("disk-denied")
        let closed = root.appendingPathComponent("closed")
        try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
        try Data(count: 40_000).write(to: closed.appendingPathComponent("inside.bin"))
        try write("open/visible.bin", in: root, bytes: 40_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: closed.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: closed.path)
        }
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: closed.path),
                      "this process can read a 000 directory, so there is nothing to refuse")

        let tree = try XCTUnwrap(DiskScanner(foldThreshold: 0).scan(root: root.path))
        let node = try XCTUnwrap(tree.children.first { $0.name == "closed" },
                                 "the unreadable folder is missing from the tree entirely")

        XCTAssertTrue(node.noAccess, """
            a folder macOS refused is drawn as a folder holding 0 bytes, with nothing saying \
            the walk never got in. The sibling it is measured against holds 40 KB.
            """)
        // The control: the walk worked, so «nothing was found» is not the reason
        // the assertion above could have passed.
        let open = try XCTUnwrap(tree.children.first { $0.name == "open" })
        XCTAssertFalse(open.noAccess)
        XCTAssertGreaterThanOrEqual(open.bytes, 40_000)
    }

    /// The `default:` case: a directory that is a file by the time the walk
    /// reaches it answers `ENOTDIR`, neither a permission nor emptiness.
    func testAPathThatIsNoLongerADirectoryIsNotReportedAsAnEmptyFolder() throws {
        let root = scratchDirectory("disk-notdir")
        let file = root.appendingPathComponent("was-a-folder")
        try Data(count: 8).write(to: file)

        let tree = try XCTUnwrap(DiskScanner(foldThreshold: 0).scan(root: file.path))

        XCTAssertTrue(tree.noAccess, """
            `open(O_DIRECTORY)` answered ENOTDIR and the walk called it an empty directory. \
            A folder Helm could not read has to be marked as one whatever stopped it — the \
            two failures left on that side of the line are a disk that is failing or has been \
            unplugged, and a directory replaced under the walk.
            """)
    }
}
