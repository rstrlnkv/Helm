import XCTest
@testable import Module_Duplicates_Engine

/// The two things the pipeline decides that nobody can check by looking: which
/// copy is offered for deletion, and in what order the groups arrive.
///
/// `DuplicatesTests` already covers both — but through assertions that cannot
/// see what they claim to check. `testAHardLinkPairPlusARealCopyStillGroups`
/// asserts a count of 2 and that `/realcopy` is in there; it never asks which
/// of the two linked names came with it, which is the only part that decides
/// what gets trashed. `testGroupsComeLargestWasteFirst` asserts
/// `wasted >= wasted`, which is true of any order when the wastes are equal.
final class DuplicatesOrderTests: XCTestCase {

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }
    private func file(_ path: String, id: UInt64, added: Int) -> FileFacts {
        FileFacts(path: path, bytes: 5_000_000, fileID: id, added: day(added))
    }

    // MARK: - The walk's order is not a decision

    /// The order `FileFacts` arrive in is directory-enumeration order: not
    /// sorted, not promised, and not the same twice on a filesystem that has
    /// been written to in between. Nothing the module answers may depend on it —
    /// least of all which file the screen offers to delete.
    ///
    /// It does. `sizeGroups` collapses hard links by keeping the *first* entry
    /// it meets for an inode, and the entry it keeps carries its own date added.
    /// Two names for one file have two different "date added" values, so which
    /// name the walk reached first decides the group's dates, and therefore its
    /// survivor.
    func testTheSameFilesInADifferentWalkOrderGiveTheSameAnswer() {
        // /h/new.bin and /h/old.bin are one file with two names (inode 7).
        // /h/other.bin is a genuine second copy of the same content.
        let newName = file("/h/new.bin", id: 7, added: 600)
        let oldName = file("/h/old.bin", id: 7, added: 100)
        let realCopy = file("/h/other.bin", id: 9, added: 300)

        let asWalkedForwards = Duplicates.groups(
            files: [newName, oldName, realCopy], minBytes: 1_000_000,
            partial: { _ in "p" }, full: { _ in "f" })
        let asWalkedBackwards = Duplicates.groups(
            files: [oldName, newName, realCopy], minBytes: 1_000_000,
            partial: { _ in "p" }, full: { _ in "f" })

        XCTAssertEqual(asWalkedForwards.map(\.paths), asWalkedBackwards.map(\.paths),
                       "the same three files, reached in a different order, must not "
                       + "produce a different offer")
    }

    /// The offer itself, stated the way the screen states it: everything after
    /// the first path is what one click puts in the basket.
    ///
    /// Deleting a hard link frees nothing — the blocks stay, held by the other
    /// name — so offering one is offering a deletion that cannot deliver the
    /// bytes the header just promised, while the copy that *would* free them
    /// stays on disk wearing the "Keep" badge.
    func testTheCopyOfferedForDeletionIsOneWhoseDeletionFreesTheBytes() {
        let newName = file("/h/new.bin", id: 7, added: 600)
        let oldName = file("/h/old.bin", id: 7, added: 100)
        let realCopy = file("/h/other.bin", id: 9, added: 300)

        let groups = Duplicates.groups(
            files: [newName, oldName, realCopy], minBytes: 1_000_000,
            partial: { _ in "p" }, full: { _ in "f" })

        XCTAssertEqual(groups.count, 1)
        let offered = groups.first?.paths.dropFirst() ?? []
        // Whichever of the linked pair represents inode 7, the extra to delete
        // is the one that owns its own blocks.
        XCTAssertEqual(Array(offered), ["/h/other.bin"],
                       "the group claims \(groups.first?.wasted ?? 0) bytes of waste; "
                       + "only deleting the copy on its own inode frees them")
    }

    // MARK: - The order of the groups themselves

    /// Groups whose waste is equal come back in whatever order
    /// `Dictionary.values` hands them over — keyed by the content digest, a
    /// string the person never sees, hashed with a seed that is new every time
    /// the app launches.
    ///
    /// So the same folder, unchanged, lists its groups in a different order
    /// after a relaunch. `SurvivingCopy` goes to the trouble of a third
    /// tiebreak so that "the row does not move between scans"; between groups
    /// nothing does.
    ///
    /// Asserted without a second process: the same files, partitioned exactly
    /// the same way, are hashed under three different digest strings. Same
    /// groups, same wastes — and three different orders.
    func testGroupOrderDoesNotDependOnTheDigestStringsNobodySees() {
        // Sixteen, not two: two orders of two groups agree half the time, and a
        // gate that passes by luck is how the last wrong survivor rule shipped.
        var files: [FileFacts] = []
        for index in 0..<16 {
            files.append(file("/g\(index)/a.bin", id: UInt64(index * 2 + 1), added: 10))
            files.append(file("/g\(index)/b.bin", id: UInt64(index * 2 + 2), added: 11))
        }
        // Every group is two copies of one 5 MB file, so every group wastes
        // exactly the same and nothing but the tiebreak can order them.
        func survivors(digestedWith salt: String) -> [String] {
            let digest: (FileFacts) -> String? = { salt + String($0.path.split(separator: "/")[0]) }
            return Duplicates.groups(files: files, minBytes: 1_000_000,
                                     partial: digest, full: digest).map { $0.paths[0] }
        }

        let plain = survivors(digestedWith: "")
        XCTAssertEqual(plain.count, 16, "sixteen groups, all wasting 5 MB")
        XCTAssertEqual(plain, survivors(digestedWith: "sha256:"))
        XCTAssertEqual(plain, survivors(digestedWith: "0123456789abcdef"))
    }
}
