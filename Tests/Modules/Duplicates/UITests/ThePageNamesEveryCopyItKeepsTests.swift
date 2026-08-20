import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The page is the only place that knows which copies are staying, so the
/// removal it sends has to say.
///
/// What a removal frees is arithmetic over clone families, and a family is held
/// by any copy of it that is not going — `DuplicateGroup.reclaimable`, the fold
/// the bar above the press is built from, counts it that way and says so. The
/// engine cannot arrive at the same figure on its own: an extra the person left
/// unticked is named in no plan, and `HelmTrash.remove`'s own doc records why it
/// cannot be recovered from the disk — there is no reverse lookup from a clone
/// family to its members. `TheBatchIsToldWhatStaysTests` holds the engine's half
/// on real clones; this holds the page's, which is that the fact is sent at all.
@MainActor
final class ThePageNamesEveryCopyItKeepsTests: XCTestCase {

    private let survivor = "\(home)/Downloads/photo.jpg"
    private let unticked = "\(home)/Downloads/photo copy.jpg"
    private let marked = "\(home)/Downloads/photo copy 2.jpg"

    /// Finder's own Duplicate command, three files deep: one original and two
    /// clones of it, of which the person ticks one.
    private var family: DuplicateGroup {
        DuplicateGroup(bytes: 4_000_000, paths: [survivor, unticked, marked])
    }

    func testTheRemovalNamesTheCopiesTheListIsKeeping() async throws {
        let wire = DuplicatesWire(groups: [family])
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(marked)

        await dvm.emptyBasket()

        XCTAssertEqual(wire.removals.last?.map(\.remove), [marked],
                       "precondition: one copy was asked for")
        let said = try XCTUnwrap(wire.staying.last, "no removal reached the wire at all")
        XCTAssertEqual(Set(said ?? []), [survivor, unticked], """
            the removal named its survivor and nothing else, so the extra left unticked — which \
            is holding its family's blocks exactly as the survivor is — was invisible to the \
            arithmetic behind the banner
            """)
    }

    /// Over the whole page, because the fold is: a clone family can have members
    /// in two groups, and `DuplicateGroup.reclaimable` opens one slate for all of
    /// them rather than one per group.
    func testItNamesTheCopiesInEveryGroupOnTheScreen() async throws {
        let elsewhere = "\(home)/Documents/note.txt"
        let wire = DuplicatesWire(groups: [family,
                                           DuplicateGroup(bytes: 1_000,
                                                          paths: [elsewhere,
                                                                  "\(home)/Documents/note 2.txt"])])
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(marked)

        await dvm.emptyBasket()

        let said = try XCTUnwrap(wire.staying.last, "no removal reached the wire at all")
        XCTAssertEqual(Set(said ?? []), [survivor, unticked, elsewhere,
                                         "\(home)/Documents/note 2.txt"],
                       "a group nothing was ticked in still holds whatever its copies hold")
    }
}
