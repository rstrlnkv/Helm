import XCTest
@testable import Module_Duplicates_Engine

/// A group's identity is its content, not the order its copies happen to be in.
///
/// Re-deciding the copy that stays permutes `copies`, and an id taken from the
/// order would make `ForEach(dvm.groups)` read a group whose survivor changed as
/// a different group — a removal and an insertion where the person made one
/// choice.
///
/// So the identity is taken from the set of paths, sorted, and the assertions
/// below are structural: they compare an id against another id of the same
/// group, never against a value a fixture could satisfy by accident.
final class AGroupsIdentityOutlivesItsOrderTests: XCTestCase {

    private func group(_ paths: [String]) -> DuplicateGroup {
        DuplicateGroup(copies: paths.map { DuplicateGroup.Copy(path: $0, bytes: 1_000_000) })
    }

    private let three = ["/Users/me/Documents/a.bin",
                         "/Users/me/Desktop/b.bin",
                         "/Users/me/Downloads/c.bin"]

    /// Whichever copy is put first, the group SwiftUI sees is the same group.
    func testTheIdDoesNotMoveWhenTheSurvivingCopyDoes() {
        let asFound = group(three)
        let reordered = group([three[2], three[0], three[1]])

        // The premise, asserted rather than assumed: these two really are in
        // different orders, or the comparison below proves nothing.
        XCTAssertNotEqual(asFound.paths, reordered.paths)
        XCTAssertEqual(asFound.id, reordered.id,
                       "the group's id followed the order of its copies — a "
                       + "re-decided survivor reads as a different group")
    }

    /// Every permutation, not the one that was thought of: the rule is about the
    /// set, so nothing in the arrangement may reach the id.
    func testEveryArrangementOfTheSameCopiesHasOneId() {
        let ids = Set(permutations(three).map { group($0).id })
        XCTAssertEqual(permutations(three).count, 6)
        XCTAssertEqual(ids.count, 1, "the same three copies answered with \(ids.count) ids")
    }

    func testGroupsOfDifferentCopiesHaveDifferentIds() {
        let one = group(three)
        let other = group([three[0], three[1], "/Users/me/Downloads/other.bin"])

        XCTAssertNotEqual(one.id, other.id,
                          "two different sets of copies share an identity")
    }

    /// A group of one copy and a group of none still answer, and answer apart.
    func testAnEmptyGroupIsNotEveryOtherEmptyGroupsTwin() {
        XCTAssertNotEqual(group([]).id, group([three[0]]).id)
    }

    /// The id is a derived value, so it must not be a place a path can be read
    /// out of. Ids reach diagnostics — the log carries no names (Architecture/DiagnosticsLog.md § Diagnostics log), and
    /// a joined list of paths would carry every one of them.
    func testTheIdDoesNotSpellThePathsItWasMadeFrom() {
        let id = group(three).id
        for path in three {
            XCTAssertFalse(id.contains(path), "the id quotes \(path)")
            XCTAssertFalse(id.contains((path as NSString).lastPathComponent),
                           "the id quotes a file name")
        }
    }
}
