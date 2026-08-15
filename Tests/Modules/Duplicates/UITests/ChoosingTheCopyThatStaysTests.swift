import HelmRuntime
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The policy is the answer for a folder; this is the answer for one group,
/// where the person knows something the rule cannot see.
///
/// **It is a rearrangement, not a second kind of state.** The whole page rests
/// on one invariant — the first copy of a group is the one that stays — and
/// every count, every plan and the background scan's own report read it. A
/// «chosen survivor» held beside the array would be a second answer to the
/// question the array already answers, and the two would part company at the
/// first removal.
@MainActor
final class ChoosingTheCopyThatStaysTests: XCTestCase {

    private let downloaded = "\(home)/Downloads/photo.jpg"
    private let filed = "\(home)/Documents/Trips/photo.jpg"
    private let archived = "\(home)/Documents/Archive/photo.jpg"

    private func trio() -> DuplicateGroup {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        return DuplicateGroup(copies: [
            .init(path: downloaded, bytes: 4_000_000, added: day),
            .init(path: filed, bytes: 4_000_000, added: day.addingTimeInterval(3600)),
            .init(path: archived, bytes: 4_000_000, added: day.addingTimeInterval(7200)),
        ])
    }

    private func searched(_ groups: [DuplicateGroup]) async -> DuplicatesViewModel {
        let dvm = DuplicatesViewModel(vm: ModuleViewModel(transport:
            DuplicatesWire(groups: groups)),
                                      store: duplicatesStore(folder: "\(home)/Downloads"),
                                      settings: SettingGuard(keys: PlantedSealKey()))
        dvm.search()
        for _ in 0..<200 where dvm.phase != .result { await Task.yield() }
        return dvm
    }

    // MARK: - The choice itself

    func testTheChosenCopyBecomesTheFirstOne() async throws {
        let dvm = await searched([trio()])
        let group = try XCTUnwrap(dvm.groups.first)
        XCTAssertNotEqual(group.paths.first, archived, "the fixture already keeps it")

        dvm.keep(archived, in: group)

        XCTAssertEqual(dvm.groups.first?.paths.first, archived)
    }

    /// The rest of the group keeps every copy it had. A choice that dropped one
    /// would be a removal nobody asked for.
    func testTheOtherCopiesAreStillThere() async throws {
        let dvm = await searched([trio()])
        dvm.keep(archived, in: try XCTUnwrap(dvm.groups.first))

        XCTAssertEqual(Set(dvm.groups.first?.paths ?? []), [downloaded, filed, archived])
    }

    /// A path that is not in that group changes nothing — a stale row, a group
    /// that has just been pruned by a removal.
    func testAPathFromAnotherGroupIsIgnored() async throws {
        let dvm = await searched([trio()])
        let before = dvm.groups.first?.paths

        dvm.keep("\(home)/Documents/somewhere-else.jpg", in: try XCTUnwrap(dvm.groups.first))

        XCTAssertEqual(dvm.groups.first?.paths, before)
    }

    /// The mark comes off, and silently: the row the person just clicked changes
    /// from a checkbox to the badge that says it stays, which is the report.
    func testTheChosenCopyComesOffTheBasket() async throws {
        let dvm = await searched([trio()])
        dvm.toggleBasket(archived)
        XCTAssertEqual(dvm.basket, [archived], "the mark this test is about was never made")

        dvm.keep(archived, in: try XCTUnwrap(dvm.groups.first))

        XCTAssertFalse(dvm.basket.contains(archived))
    }

    // MARK: - And the policy leaves it alone

    func testAGroupChosenByHandIsNotRearrangedByAPolicyChange() async throws {
        let dvm = await searched([trio()])
        dvm.choose(.byDate)
        dvm.keep(archived, in: try XCTUnwrap(dvm.groups.first))

        dvm.choose(.byPlace)

        XCTAssertEqual(dvm.groups.first?.paths.first, archived,
                       "the policy overruled a choice the person made about this group")
    }

    /// And every other group follows the new policy, or the pin would be a way
    /// of freezing the whole page.
    func testTheGroupsNobodyChoseStillFollowThePolicy() async throws {
        let other = DuplicateGroup(copies: [
            .init(path: "\(home)/Downloads/note.pdf", bytes: 2_000_000,
                  added: Date(timeIntervalSince1970: 1_700_000_000)),
            .init(path: "\(home)/Documents/note.pdf", bytes: 2_000_000,
                  added: Date(timeIntervalSince1970: 1_700_003_600)),
        ])
        let dvm = await searched([trio(), other])
        dvm.choose(.byDate)
        dvm.keep(archived, in: try XCTUnwrap(dvm.groups.first))

        dvm.choose(.byPlace)

        XCTAssertEqual(dvm.groups.last?.paths.first, "\(home)/Documents/note.pdf")
    }

    func testTheRecommendationCanBePutBack() async throws {
        let dvm = await searched([trio()])
        // A policy chosen outright, so the order on screen is one the rule
        // produced: the fake wire hands back the fixture as it was written, and
        // a «recommendation» read off that would be whatever the test typed.
        dvm.choose(.byDate)
        let recommended = try XCTUnwrap(dvm.groups.first?.paths.first)
        XCTAssertNotEqual(recommended, archived, "the choice below would change nothing")
        dvm.keep(archived, in: try XCTUnwrap(dvm.groups.first))

        dvm.restoreRecommendation(for: try XCTUnwrap(dvm.groups.first))

        XCTAssertEqual(dvm.groups.first?.paths.first, recommended)
    }

    /// Putting it back releases the group, or the next policy change would still
    /// step over a group nobody has an opinion about any more.
    func testAGroupPutBackFollowsThePolicyAgain() async throws {
        let dvm = await searched([trio()])
        dvm.choose(.byDate)
        dvm.keep(archived, in: try XCTUnwrap(dvm.groups.first))
        dvm.restoreRecommendation(for: try XCTUnwrap(dvm.groups.first))

        dvm.choose(.byPlace)

        XCTAssertEqual(dvm.groups.first?.paths.first, filed)
    }

    /// A search re-reads the folder and re-decides everything, which is what
    /// pressing Search again asks for. The choice belonged to the list it is
    /// replacing — and the same content found again has the same id, so a pin
    /// held across a search would step over the new answer with nothing on
    /// screen to say why.
    func testASearchForgetsTheChoicesItReplaces() async throws {
        let dvm = await searched([trio()])
        dvm.choose(.byDate)
        dvm.keep(archived, in: try XCTUnwrap(dvm.groups.first))

        dvm.search()
        for _ in 0..<200 where dvm.phase != .result { await Task.yield() }
        dvm.choose(.byPlace)

        // The rung, whichever it is, rather than `.byHand`: both filed copies
        // clear the transit tier, so what separates them is the date — the
        // reason is about the survivor and the copy that came closest, not about
        // the policy's name.
        XCTAssertEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .rung(.date))
        XCTAssertEqual(dvm.groups.first?.paths.first, filed)
    }

    // MARK: - What the header says about it

    func testAGroupChosenByHandSaysSo() async throws {
        let dvm = await searched([trio()])
        dvm.keep(archived, in: try XCTUnwrap(dvm.groups.first))

        XCTAssertEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .byHand)
    }

    /// One fixture per rung of the ladder, because the header reads the rung that
    /// actually separated the survivor from the copy that came closest — not the
    /// policy's name. Every branch, so a rung that stops being reachable is a
    /// failure here rather than a header that quietly says the same thing about
    /// everything.
    func testEveryRungOfTheLadderCanBeWhatTheHeaderSays() async throws {
        let noon = Date(timeIntervalSince1970: 1_700_000_000)
        let cases: [(KeepReason, [DuplicateGroup.Copy])] = [
            // One copy is in transit and the other is filed: the tier decides
            // before anything else is asked.
            (.place, [.init(path: downloaded, bytes: 9, added: noon),
                      .init(path: filed, bytes: 9, added: noon)]),
            // Both filed, so the tier says nothing and the dates do.
            (.date, [.init(path: filed, bytes: 9, added: noon),
                     .init(path: archived, bytes: 9, added: noon.addingTimeInterval(60))]),
            // Same day to the second — which a filesystem really does report for
            // files that arrived together — so how far in they sit decides.
            (.depth, [.init(path: "\(home)/Documents/photo.jpg", bytes: 9, added: noon),
                      .init(path: archived, bytes: 9, added: noon)]),
            // Alike in every way the rule can see. The alphabet is a fact about
            // their spelling and nothing else, which is why it has to be visible.
            (.name, [.init(path: "\(home)/Documents/a.jpg", bytes: 9, added: noon),
                     .init(path: "\(home)/Documents/b.jpg", bytes: 9, added: noon)]),
        ]
        for (rung, copies) in cases {
            let dvm = await searched([DuplicateGroup(copies: copies)])
            dvm.choose(.byDate)
            dvm.choose(.byPlace)

            XCTAssertEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .rung(rung),
                           "the group built for \(rung.rawValue) was decided by something else")
        }
    }

    /// And the rung follows the policy, since the ladder is ordered by it.
    func testTheRungFollowsThePolicy() async throws {
        let noon = Date(timeIntervalSince1970: 1_700_000_000)
        let dvm = await searched([DuplicateGroup(copies: [
            .init(path: downloaded, bytes: 9, added: noon),
            .init(path: filed, bytes: 9, added: noon.addingTimeInterval(60)),
        ])])

        dvm.choose(.byDate)
        XCTAssertEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .rung(.date))

        dvm.choose(.byPlace)
        XCTAssertEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .rung(.place))
    }

    /// «Mark every extra copy» reads the array, so a hand-chosen survivor is the
    /// one copy it leaves alone. This is the button that acts on the whole page
    /// at once, and it is where a second notion of «the survivor» would show up
    /// as somebody's file in the Trash.
    func testMarkingEveryExtraRespectsTheChoice() async throws {
        let dvm = await searched([trio()])
        dvm.keep(archived, in: try XCTUnwrap(dvm.groups.first))

        dvm.basketAllExtras()

        XCTAssertEqual(Set(dvm.basket), [downloaded, filed])
    }
}
