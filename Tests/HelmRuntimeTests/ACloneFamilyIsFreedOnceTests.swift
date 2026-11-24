import Darwin
import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// What a removal may say it freed, when the files share their blocks.
///
/// On APFS a clone shares its blocks with the file it was made from, and
/// Finder's Duplicate command makes clones, so this is the ordinary case. A file
/// and its clone each report their full allocation and the second costs no free
/// space; weighed one at a time they would announce twice the space the disk
/// gives back.
///
/// `CloneShare` in `HelmRuntime` is the arithmetic: a family is charged once,
/// not once per member.
///
/// Nothing here is trashed: `HelmTrash`'s injected `trashing` closure does
/// nothing, so what is measured is the ledger, and the files stay in the
/// scratch directory.
final class ACloneFamilyIsFreedOnceTests: XCTestCase {

    private var root: URL!
    private let bytes = 400_000

    override func setUpWithError() throws {
        root = scratchDirectory("disk-clones")
    }

    /// A file, and a clone of it: one allocation, two names, and the same clone
    /// family id.
    private func original(_ name: String) throws -> URL {
        try write(name, in: root, bytes: bytes)
    }

    private func clone(of url: URL, as name: String) throws -> URL {
        let copy = root.appendingPathComponent(name)
        // `clonefile(2)`, so the sharing is made rather than hoped for, and
        // asserted below either way.
        guard clonefile(url.path, copy.path, 0) == 0 else {
            throw XCTSkip("this volume does not clone: errno \(errno)")
        }
        return copy
    }

    private func allocated(_ url: URL) -> Int {
        var seen: Set<UInt64> = []
        return FileWeight.allocated(of: url, countingOnce: &seen)
    }

    /// Two names for one allocation are charged once.
    func testAFamilyRemovedWholeIsChargedOnce() throws {
        let first = try original("a.bin")
        let second = try clone(of: first, as: "b.bin")
        XCTAssertEqual(CloneShare.familyID(ofFileAt: first.path),
                       CloneShare.familyID(ofFileAt: second.path),
                       "precondition: the two really do share their blocks")
        let one = allocated(first)
        XCTAssertGreaterThan(one, 0, "precondition: the file has blocks to give back")

        let result = HelmTrash.remove(allowed: [first.path, second.path],
                                      module: "disk", trashing: { try FileManager.default.removeItem(at: $0) })

        XCTAssertEqual(result.removed.count, 2, "precondition: both were taken")
        XCTAssertEqual(result.freedBytes, one, """
            a clone family was charged once per member: \(result.freedBytes) bytes announced for \
            \(one) bytes of blocks. The disk gives back the family's blocks once.
            """)
    }

    /// And the same inside a folder, which is what a basket row usually is: the
    /// walk charges the family once, not once per name it meets.
    func testAFamilyInsideAFolderIsChargedOnce() throws {
        let folder = root.appendingPathComponent("holder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("holder/a.bin")
        try Data(repeating: 0x41, count: bytes).write(to: first)
        guard clonefile(first.path, root.appendingPathComponent("holder/b.bin").path, 0) == 0 else {
            throw XCTSkip("this volume does not clone: errno \(errno)")
        }
        let one = allocated(first)

        let result = HelmTrash.remove(allowed: [folder.path], module: "disk", trashing: { try FileManager.default.removeItem(at: $0) })

        XCTAssertEqual(result.removed, [folder.path], "precondition: the folder was taken")
        XCTAssertEqual(result.freedBytes, one,
                       "a clone family inside a folder was charged once per member")
    }

    /// The control: two files that share nothing are two allocations, and a
    /// ledger that answered "once" for everything would pass the tests above.
    func testTwoUnrelatedFilesAreBothCharged() throws {
        let first = try original("a.bin")
        let second = try original("b.bin")
        XCTAssertNotEqual(CloneShare.familyID(ofFileAt: first.path),
                          CloneShare.familyID(ofFileAt: second.path),
                          "precondition: these two share nothing")

        // Read before the removal: a removed file allocates nothing.
        let expected = allocated(first) + allocated(second)

        let result = HelmTrash.remove(allowed: [first.path, second.path],
                                      module: "disk", trashing: { try FileManager.default.removeItem(at: $0) })

        XCTAssertEqual(result.freedBytes, expected,
                       "two separate allocations were reported as one")
    }

    /// A hard link is the other way one allocation wears two names. Both rules
    /// run over the same batch, so neither may cost the other.
    func testAHardLinkIsStillChargedOnce() throws {
        let first = try original("a.bin")
        let link = root.appendingPathComponent("same.bin")
        try FileManager.default.linkItem(at: first, to: link)
        let expected = allocated(first)

        let result = HelmTrash.remove(allowed: [first.path, link.path],
                                      module: "disk", trashing: { try FileManager.default.removeItem(at: $0) })

        XCTAssertEqual(result.freedBytes, expected,
                       "a hard link's second name freed a second allocation")
    }

    /// A path that is refused spends nothing: the ledger grows only where the
    /// batch really took something, as with the inode set, which is why it is
    /// copied per path rather than written to.
    func testARefusedPathLeavesTheFamilyUncharged() throws {
        let first = try original("a.bin")
        let second = try clone(of: first, as: "b.bin")
        let one = allocated(first)

        // The first path refuses; the second is its clone and must still be
        // charged, because nothing has been taken yet.
        let result = HelmTrash.remove(
            allowed: [first.path, second.path], module: "disk",
            trashing: { url in
                if url.lastPathComponent == "a.bin" {
                    throw NSError(domain: NSCocoaErrorDomain, code: 513)
                }
                try FileManager.default.removeItem(at: url)
            })

        XCTAssertEqual(result.removed, [second.path], "precondition: one refused, one taken")
        XCTAssertEqual(result.freedBytes, one,
                       "the refused path spent the family's blocks and the taken one freed nothing")
    }
}
