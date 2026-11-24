import XCTest
@testable import Module_Duplicates_Engine

/// **The ladder must be transitive, or the survivor is a fact about the array
/// rather than about the copies.**
///
/// `SurvivingCopy.order` is `files.sorted { decide($0, over: $1, by: rule).keepsFirst }`,
/// and `decide` answers with the *first rung that can tell the two apart*. That
/// composition is a strict weak ordering only while every rung either separates
/// every pair or none of them. A `.date` rung that is silent when one date is
/// blank makes a dateless copy *incomparable* with every other, and three
/// copies close a cycle:
///
///   • Mirror (no date) beats Sync — the date rung is silent, the alphabet decides.
///   • Sync beats Archive — both dates are known, and Sync's is the earlier.
///   • Archive beats Mirror — the date rung is silent again, and the alphabet
///     decides the other way.
///
/// `Swift.sorted(by:)` given that predicate hands back whichever copy the input
/// order fed it first, so the walk would decide which of somebody's copies is
/// offered for the Trash.
///
/// **Three copies, not two.** Two elements cannot hold a cycle, so a reversed
/// pair is green for every predicate this file can write: a check whose subject
/// cannot exhibit the defect (Architecture/TestsAndMeasurement.md § What makes a check).
///
/// The fixture is machine-independent on purpose: `TransitFolders(roots: [])`
/// rather than `.system`, so the `.place` rung is silent for every path here and
/// nothing depends on where this Mac keeps Downloads.
final class TheSurvivorDoesNotDependOnWalkOrderTests: XCTestCase {

    /// Three copies at one depth, in one tier, one of them with no Date Added.
    ///
    /// Alphabetically Archive < Mirror < Sync, and the two dates run the other way:
    /// Sync arrived on day 100, Archive on day 400. Mirror has no date at all —
    /// restored from a backup, or written by a tool that never set the attribute,
    /// which is the `nil` `KeepCandidate.added` is documented to carry.
    private var copies: [FileFacts] {
        [facts("/Users/r/Archive/photo.jpg", added: day(400)),
         facts("/Users/r/Mirror/photo.jpg", added: nil),
         facts("/Users/r/Sync/photo.jpg", added: day(100))]
    }

    /// Every ordering the walk could have handed over, and what each one keeps.
    private func survivorsOverEveryWalkOrder(_ files: [FileFacts],
                                             _ rule: KeepRule) -> [String: [String]] {
        var found: [String: [String]] = [:]
        for order in permutations(files) {
            let survivor = SurvivingCopy.order(order, by: rule)[0].path
            found[survivor, default: []].append(order.map(\.path).joined(separator: " → "))
        }
        return found
    }

    /// The pairwise readings, printed in the failure so the cycle is named rather
    /// than inferred: whichever of the three is reported, the reader can see why.
    private func ladderReadings(_ files: [FileFacts], _ rule: KeepRule) -> String {
        var lines: [String] = []
        for a in files.indices {
            for b in files.indices where b > a {
                let winner = SurvivingCopy.order([files[a], files[b]], by: rule)[0].path
                lines.append("  \(files[a].path) vs \(files[b].path) → keeps \(winner)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - The finding

    /// **The survivor changes with the order the walk found the copies in.**
    ///
    /// Asked of both policies, because the cycle is closed by `.date` and `.name`
    /// and both ladders carry both rungs — `byPlace` is only the standard one.
    func testTheSurvivorIsTheSameWhateverOrderTheWalkFoundTheCopiesIn() {
        for policy in KeepPolicy.allCases {
            let rule = rule(policy)
            let survivors = survivorsOverEveryWalkOrder(copies, rule)
            XCTAssertEqual(survivors.count, 1, """
                policy «\(policy.rawValue)»: the six orderings of one group of three copies \
                keep \(survivors.count) different files. Which copy Helm keeps — and \
                therefore which two it offers for the Trash — is decided by the order the \
                walk happened to build the array in, not by the copies.

                kept, and the walk orders that keep it:
                \(survivors.map { "  \($0.key)\n    from \($0.value.joined(separator: "\n    from "))" }
                    .sorted().joined(separator: "\n"))

                the ladder read pairwise, which is where the cycle is:
                \(ladderReadings(copies, rule))

                `SurvivingCopy.decide` answers with the first rung that separates two \
                copies, and `.date` separates nothing when one of the two has no Date \
                Added. Incomparability does not compose, so the three pairwise answers \
                close a cycle and `Swift.sorted(by:)` is being given a predicate that is \
                not a strict weak ordering.
                """)
        }
    }

    /// **Copies that tie on every rung above the path are still ordered by it.**
    ///
    /// The three-copy fixture above is settled by `.undated` before `.name` is
    /// reached, so it stays green with the path tie-break gone. Two copies of one
    /// depth, in one tier, with the same Date Added are separated by nothing but
    /// their paths, and the survivor must not be whichever the walk met first.
    func testCopiesTyingOnEveryRungAreSeparatedByTheirPaths() {
        let tied = [facts("/Users/r/B/photo.jpg", added: day(7)),
                    facts("/Users/r/A/photo.jpg", added: day(7))]
        for policy in KeepPolicy.allCases {
            let survivors = survivorsOverEveryWalkOrder(tied, rule(policy))
            XCTAssertEqual(Array(survivors.keys), ["/Users/r/A/photo.jpg"],
                           "policy «\(policy.rawValue)»: the survivor of a full tie follows the walk order")
        }
    }

    /// The same cycle, said as the thing the module promises: the copy that stays
    /// is the copy that stays, whichever two it is compared against.
    ///
    /// Separate from the permutation test because it fails for a different reason —
    /// an ordering can be stable under permutation and still keep a copy that loses
    /// its own pairwise reading, as one that only sorts the input would.
    func testTheKeptCopyBeatsEveryOtherCopyOneAtATime() {
        for policy in KeepPolicy.allCases {
            let rule = rule(policy)
            let group = copies
            let kept = SurvivingCopy.order(group, by: rule)[0]
            let lost = group.filter { $0.path != kept.path }
                .filter { SurvivingCopy.order([kept, $0], by: rule)[0].path != kept.path }
            XCTAssertEqual(lost.map(\.path), [], """
                policy «\(policy.rawValue)»: the group keeps \(kept.path), and asked about \
                that copy against \(lost.count) of the others one at a time the same ladder \
                keeps the other one. The copy on screen under «Keeping» is not the copy the \
                rule picks.

                the ladder read pairwise:
                \(ladderReadings(group, rule))
                """)
        }
    }

    // MARK: - Controls

    /// **The control for the harness.** The same three paths, the same permutation
    /// machinery, every date known — one survivor out of six orderings.
    ///
    /// Without it, the test above proves only that permuting an array can change an
    /// answer, which is true of any unstable sort and of nothing worth reporting.
    /// With it, what is left is the dateless copy.
    func testWithEveryDateKnownTheSurvivorIsOneWhateverTheWalkOrderWas() {
        let dated = [facts("/Users/r/Archive/photo.jpg", added: day(400)),
                     facts("/Users/r/Mirror/photo.jpg", added: day(250)),
                     facts("/Users/r/Sync/photo.jpg", added: day(100))]
        for policy in KeepPolicy.allCases {
            let survivors = survivorsOverEveryWalkOrder(dated, rule(policy))
            XCTAssertEqual(survivors.keys.sorted(), ["/Users/r/Sync/photo.jpg"],
                           "policy «\(policy.rawValue)»: three known dates are a total order "
                           + "on this group, and the earliest copy stays whatever order the "
                           + "walk handed them over in")
        }
    }

    /// **The second control: one blank date is not by itself a cycle.** Two copies,
    /// one dateless, permuted both ways — one survivor.
    ///
    /// So the rule is not «a `nil` date makes the ordering unstable», which would
    /// invite treating an unknown date as a loss (kept out by
    /// `KeepPolicyTests.testAnUnknownDateIsARungOfItsOwnAndTheCopyItIsMissingFromStays`).
    /// It takes a third copy for the silent rung to compose with a speaking one.
    func testOneDatelessCopyAgainstOneDatedCopyIsStillDecided() {
        let pair = [facts("/Users/r/Mirror/photo.jpg", added: nil),
                    facts("/Users/r/Sync/photo.jpg", added: day(100))]
        for policy in KeepPolicy.allCases {
            let survivors = survivorsOverEveryWalkOrder(pair, rule(policy))
            XCTAssertEqual(survivors.count, 1,
                           "policy «\(policy.rawValue)»: two copies cannot hold a cycle")
        }
    }

    /// And the permutation harness itself answers over a subject that has no order
    /// to disagree about, so a green result above is a reading and not a skip.
    func testThePermutationHarnessCoversEveryOrdering() {
        XCTAssertEqual(permutations([1, 2, 3]).count, 6)
        XCTAssertEqual(Set(permutations([1, 2, 3]).map { $0.map(String.init).joined() }).count, 6)
    }
}
