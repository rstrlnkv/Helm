import Darwin
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Disk_Engine

/// What a removal may say it freed, when the files share their blocks.
///
/// On APFS a **clone** shares its blocks with the file it was made from, and
/// Finder's Duplicate command makes clones — so this is the ordinary case, not an
/// exotic one. Measured in a scratch directory: one 20 MB file and a clone of it
/// report the same clone family id, each report 20 000 768 allocated bytes, and
/// the second one cost **0 bytes** of free space. `HelmTrash` weighed them one at
/// a time and announced 40 MB freed for 20 MB of blocks; the ring above says the
/// same thing, and «Moved to the Trash — 8 GB» is a promise about space the disk
/// will not give back.
///
/// `CloneShare` — in `HelmRuntime`, and used by Duplicates since the day this was
/// measured — is the arithmetic: a family is charged once, not once per member.
/// `grep -rn CloneShare Sources/Modules/Disk` was empty, which is the house rule
/// about shared plumbing read from the wrong side.
///
/// **Nothing here is trashed.** The move is `HelmTrash`'s injected `trashing`
/// closure and it does nothing, so what is measured is the ledger and the files
/// stay in the scratch directory the teardown drains.
final class ACloneFamilyIsFreedOnceTests: XCTestCase {

    private var root: URL!
    private let bytes = 400_000

    override func setUpWithError() throws {
        root = scratchDirectory("disk-clones")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A file, and a clone of it: one allocation, two names, and the same clone
    /// family id.
    private func original(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    private func clone(of url: URL, as name: String) throws -> URL {
        let copy = root.appendingPathComponent(name)
        // `clonefile(2)` rather than `cp -c` or `copyItem`: this test's whole
        // subject is that the two share blocks, so the sharing is made rather
        // than hoped for — and asserted below either way.
        guard clonefile(url.path, copy.path, 0) == 0 else {
            throw XCTSkip("this volume does not clone: errno \(errno)")
        }
        return copy
    }

    private func allocated(_ url: URL) -> Int {
        var seen: Set<UInt64> = []
        return FileWeight.allocated(of: url, countingOnce: &seen)
    }

    /// The defect: two names for one allocation, charged twice.
    func testAFamilyRemovedWholeIsChargedOnce() throws {
        let first = try original("a.bin")
        let second = try clone(of: first, as: "b.bin")
        XCTAssertEqual(CloneShare.familyID(ofFileAt: first.path),
                       CloneShare.familyID(ofFileAt: second.path),
                       "precondition: the two really do share their blocks")
        let one = allocated(first)
        XCTAssertGreaterThan(one, 0, "precondition: the file has blocks to give back")

        let result = HelmTrash.remove(allowed: [first.path, second.path],
                                      module: "disk", trashing: { _ in })

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

        let result = HelmTrash.remove(allowed: [folder.path], module: "disk", trashing: { _ in })

        XCTAssertEqual(result.removed, [folder.path], "precondition: the folder was taken")
        XCTAssertEqual(result.freedBytes, one,
                       "a clone family inside a folder was charged once per member")
    }

    /// The control, and it is the half that matters most: two files that share
    /// nothing are two allocations, and a ledger that answered "once" for
    /// everything would pass the test above while under-reporting every ordinary
    /// removal there is.
    func testTwoUnrelatedFilesAreBothCharged() throws {
        let first = try original("a.bin")
        let second = try original("b.bin")
        XCTAssertNotEqual(CloneShare.familyID(ofFileAt: first.path),
                          CloneShare.familyID(ofFileAt: second.path),
                          "precondition: these two share nothing")

        let result = HelmTrash.remove(allowed: [first.path, second.path],
                                      module: "disk", trashing: { _ in })

        XCTAssertEqual(result.freedBytes, allocated(first) + allocated(second),
                       "two separate allocations were reported as one")
    }

    /// A hard link is the other way one allocation wears two names, and it was
    /// already handled. Both rules run over the same batch, so this is the guard
    /// that adding the second did not cost the first.
    func testAHardLinkIsStillChargedOnce() throws {
        let first = try original("a.bin")
        let link = root.appendingPathComponent("same.bin")
        try FileManager.default.linkItem(at: first, to: link)

        let result = HelmTrash.remove(allowed: [first.path, link.path],
                                      module: "disk", trashing: { _ in })

        XCTAssertEqual(result.freedBytes, allocated(first),
                       "a hard link's second name freed a second allocation")
    }

    /// A path that is refused spends nothing: the ledger grows only where the
    /// batch really took something, which is the rule the inode set already
    /// follows and the reason it is copied per path rather than written to.
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
            })

        XCTAssertEqual(result.removed, [second.path], "precondition: one refused, one taken")
        XCTAssertEqual(result.freedBytes, one,
                       "the refused path spent the family's blocks and the taken one freed nothing")
    }
}
