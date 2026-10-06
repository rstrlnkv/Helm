import HelmContract
import HelmRuntime
import HelmUI
import XCTest
@testable import HelmApp

/// **The sidebar's rows are a pure value of two things, the arrangement and the
/// set of modules switched on: a module that is off is not a row, a section left
/// with no module has no heading, the foot row is always there, and a selection
/// whose module is off reads as General.**
///
/// No view, no window: `ShellSidebarRows` is built from a `SidebarLayout` and a
/// set of ids, and every question about it, which row a selection selects, which
/// row an arrow key lands on, whether a module is blocked, what a selection
/// becomes, is answered from values. This class is deliberately not
/// `@MainActor`, so a type bound to the main actor would not compile here.
///
/// The tests build their own layouts out of invented ids (`alpha`, `beta`, ...);
/// none of them needs a real module to exist.
///
/// What the inputs are not told, and what was chosen (each is written in the
/// test that holds it):
/// - a module held by two sections is one row, in its first section;
/// - an enabled id that no section holds is not a row;
/// - a selection that leads to no row selects nothing (nil), and so does nil;
/// - `neighbour` of a row that is not in the list is nil, and so is a step past
///   either end: the list stops, it does not wrap;
/// - `settled` asks only whether the module is on, not whether a section holds
///   it.
final class TheSidebarListsOnlyWhatIsOnTests: XCTestCase {

    // MARK: - inputs

    private typealias Rows = ShellSidebarRows

    /// Two sections of two modules each, both named by hand and neither seeded.
    private static let layout = SidebarLayout(sections: [
        .init(id: "s1", seed: nil, name: "First", modules: ["alpha", "beta"]),
        .init(id: "s2", seed: nil, name: "Second", modules: ["gamma", "delta"]),
    ])

    private static let allOn: Set<String> = ["alpha", "beta", "gamma", "delta"]

    private func rows(_ layout: SidebarLayout = layout, on enabled: Set<String>) -> Rows {
        Rows(layout: layout, enabled: enabled)
    }

    private func modules(_ rows: Rows) -> [String] {
        rows.rows.compactMap { if case .module(let id) = $0 { id } else { nil } }
    }

    // MARK: - what is a row

    func testAModuleSwitchedOffIsNotARow() {
        // beta is off; gamma and delta are off, so the whole second section is.
        let rows = rows(on: ["alpha"])
        XCTAssertEqual(modules(rows), ["alpha"], "a switched-off module is still a row")
        XCTAssertEqual(rows.groups.map(\.section.id), ["s1"],
                       "a section whose every module is off still has a heading")
        XCTAssertEqual(rows.groups.first?.modules, ["alpha"])
        XCTAssertEqual(rows.rows, [.module("alpha"), .foot])
    }

    func testAModuleThatIsOnKeepsItsSectionAndItsOrder() {
        let rows = rows(on: Self.allOn)
        XCTAssertEqual(rows.groups.map(\.section.id), ["s1", "s2"])
        XCTAssertEqual(rows.groups.map(\.modules), [["alpha", "beta"], ["gamma", "delta"]])
        XCTAssertEqual(rows.rows,
                       [.module("alpha"), .module("beta"), .module("gamma"), .module("delta"), .foot])
    }

    func testAGroupKeepsTheSectionItWasMadeFromSoItCanBeTitled() {
        // A drawer titles it with `AppStr.sectionTitle`, which takes the section.
        let rows = rows(on: Self.allOn)
        XCTAssertEqual(rows.groups.map(\.section), Self.layout.sections)
        XCTAssertEqual(AppStr.sectionTitle(rows.groups[0].section), "First")
    }

    func testTheFootRowIsOneAndLastWhateverIsOn() {
        for enabled in [Self.allOn, ["beta"], []] as [Set<String>] {
            let rows = rows(on: enabled)
            XCTAssertEqual(rows.rows.filter { $0 == .foot }.count, 1,
                           "the sidebar has not exactly one foot row")
            XCTAssertEqual(rows.rows.last, .foot)
        }
    }

    func testNothingOnLeavesOnlyTheFootRow() {
        let rows = rows(on: [])
        XCTAssertEqual(rows.rows, [.foot],
                       "the sidebar is empty: no module rows at all, only the foot row")
        XCTAssertTrue(rows.groups.isEmpty)
    }

    func testALayoutWithNoSectionsLeavesOnlyTheFootRow() {
        // Even with ids switched on: nothing holds them.
        let rows = rows(SidebarLayout(sections: []), on: Self.allOn)
        XCTAssertEqual(rows.rows, [.foot],
                       "the sidebar is empty: no module rows at all, only the foot row")
        XCTAssertTrue(rows.groups.isEmpty)
    }

    func testASectionWithNoModulesHasNoHeadingEvenWhenEverythingIsOn() {
        let layout = SidebarLayout(sections: [
            .init(id: "empty", seed: nil, name: "Empty", modules: []),
            .init(id: "s", seed: nil, name: "S", modules: ["alpha"]),
        ])
        XCTAssertEqual(rows(layout, on: ["alpha"]).groups.map(\.section.id), ["s"])
    }

    func testAnEnabledIdNoSectionHoldsIsNotARow() {
        let rows = rows(on: Self.allOn.union(["orphan"]))
        XCTAssertFalse(modules(rows).contains("orphan"),
                       "a module no section holds is drawn as a row")
        XCTAssertEqual(modules(rows), ["alpha", "beta", "gamma", "delta"])
    }

    func testAModuleListedInTwoSectionsIsOneRowInTheFirst() {
        let layout = SidebarLayout(sections: [
            .init(id: "s1", seed: nil, name: "First", modules: ["alpha"]),
            .init(id: "s2", seed: nil, name: "Second", modules: ["alpha", "beta"]),
        ])
        let rows = rows(layout, on: ["alpha", "beta"])
        XCTAssertEqual(modules(rows), ["alpha", "beta"], "a module is drawn twice")
        XCTAssertEqual(rows.groups.map(\.modules), [["alpha"], ["beta"]])

        // The second section holds only the repeat: it has no heading.
        let onlyAlpha = self.rows(layout, on: ["alpha"])
        XCTAssertEqual(onlyAlpha.groups.map(\.section.id), ["s1"])
        XCTAssertEqual(onlyAlpha.rows, [.module("alpha"), .foot])
    }

    // MARK: - which row is selected

    func testTheThreeSettingsSelectionsSelectTheFootRow() {
        let rows = rows(on: Self.allOn)
        XCTAssertEqual(rows.row(for: .general), .foot)
        XCTAssertEqual(rows.row(for: .log), .foot)
        XCTAssertEqual(rows.row(for: .about), .foot)
    }

    func testAModuleSelectionSelectsItsRowOnlyWhileItIsOne() {
        XCTAssertEqual(rows(on: Self.allOn).row(for: .module("gamma")), .module("gamma"))
        // Off, in no section, and unknown: no row leads there, so nothing is selected.
        XCTAssertNil(rows(on: ["alpha"]).row(for: .module("gamma")))
        XCTAssertNil(rows(on: Self.allOn).row(for: .module("orphan")))
        XCTAssertNil(rows(on: []).row(for: .module("alpha")))
    }

    func testNoSelectionSelectsNoRow() {
        XCTAssertNil(rows(on: Self.allOn).row(for: nil))
        XCTAssertNil(rows(on: []).row(for: nil))
    }

    func testTheFootRowIsSelectedEvenWhenItIsTheOnlyRow() {
        XCTAssertEqual(rows(on: []).row(for: .about), .foot)
    }

    // MARK: - the arrow keys

    func testNeighbourMovesAcrossASectionBoundary() {
        let rows = rows(on: Self.allOn)
        XCTAssertEqual(rows.neighbour(of: .module("beta"), moving: .down), .module("gamma"))
        XCTAssertEqual(rows.neighbour(of: .module("gamma"), moving: .up), .module("beta"))
    }

    func testNeighbourStopsAtBothEnds() {
        let rows = rows(on: Self.allOn)
        XCTAssertNil(rows.neighbour(of: .module("alpha"), moving: .up), "the list wrapped at the top")
        XCTAssertNil(rows.neighbour(of: .foot, moving: .down), "the list wrapped at the foot")
    }

    func testNeighbourReachesTheFootRowFromTheLastModuleAndBack() {
        let rows = rows(on: Self.allOn)
        XCTAssertEqual(rows.neighbour(of: .module("delta"), moving: .down), .foot)
        XCTAssertEqual(rows.neighbour(of: .foot, moving: .up), .module("delta"))
    }

    func testNeighbourSkipsWhatIsOff() {
        let rows = rows(on: ["alpha", "delta"])
        XCTAssertEqual(rows.neighbour(of: .module("alpha"), moving: .down), .module("delta"))
        XCTAssertEqual(rows.neighbour(of: .module("delta"), moving: .up), .module("alpha"))
    }

    func testNeighbourOfARowThatIsNotInTheListIsNil() {
        // Chosen: no guess at where the person was; the caller decides.
        let rows = rows(on: ["alpha"])
        XCTAssertNil(rows.neighbour(of: .module("beta"), moving: .down))
        XCTAssertNil(rows.neighbour(of: .module("beta"), moving: .up))
        XCTAssertNil(rows.neighbour(of: .module("orphan"), moving: .down))
    }

    func testNeighbourWithOnlyTheFootRowStaysPut() {
        let rows = rows(on: [])
        XCTAssertNil(rows.neighbour(of: .foot, moving: .up))
        XCTAssertNil(rows.neighbour(of: .foot, moving: .down))
    }

    // MARK: - blocked

    private func blocked(_ needs: [ModulePermission],
                         disk: PermissionState = .granted,
                         accessibility: PermissionState = .granted,
                         screenRecording: PermissionState = .granted) -> Bool {
        Rows.blocked(inertWithout: needs, disk: disk, accessibility: accessibility,
                     screenRecording: screenRecording)
    }

    func testEachNeedIsBlockedByItsOwnDeniedPermissionOnly() {
        XCTAssertTrue(blocked([.fullDisk], disk: .denied))
        XCTAssertTrue(blocked([.accessibility], accessibility: .denied))
        XCTAssertTrue(blocked([.screenRecording], screenRecording: .denied))

        // A different permission being denied says nothing about this need.
        XCTAssertFalse(blocked([.fullDisk], accessibility: .denied, screenRecording: .denied))
        XCTAssertFalse(blocked([.accessibility], disk: .denied, screenRecording: .denied))
        XCTAssertFalse(blocked([.screenRecording], disk: .denied, accessibility: .denied))
    }

    func testAGrantedPermissionDoesNotBlock() {
        // PermissionState is not CaseIterable, so its cases cannot be enumerated
        // here; this list names every non-denied case by hand (today only
        // .granted) and must be extended when a case is added.
        for state in [PermissionState.granted] {
            for need in ModulePermission.allCases {
                XCTAssertFalse(blocked([need], disk: state, accessibility: state, screenRecording: state),
                               "\(need) blocks while its permission is \(state)")
            }
        }
    }

    func testAModuleThatDeclaredNothingIsNeverBlocked() {
        XCTAssertFalse(blocked([], disk: .denied, accessibility: .denied, screenRecording: .denied))
    }

    func testTheAdminHelperNeverBlocks() {
        XCTAssertFalse(blocked([.adminHelper], disk: .denied, accessibility: .denied,
                               screenRecording: .denied))
    }

    func testSeveralNeedsAreBlockedWhenAnyOneOfThemIsDenied() {
        let needs: [ModulePermission] = [.fullDisk, .accessibility, .screenRecording]
        XCTAssertTrue(blocked(needs, screenRecording: .denied))
        XCTAssertTrue(blocked(needs, disk: .denied))
        XCTAssertFalse(blocked(needs))
        // The admin helper next to a denied need does not hide it, nor does it add one.
        XCTAssertTrue(blocked([.adminHelper, .accessibility], accessibility: .denied))
        XCTAssertFalse(blocked([.adminHelper, .accessibility], disk: .denied))
    }

    // MARK: - settled

    func testAModuleSwitchedOffUnderThePersonReadsAsGeneral() {
        XCTAssertEqual(Rows.settled(.module("disk"), enabled: []), .general,
                       "a module switched off under the person stays selected: the pane shows a page no row leads to")
        XCTAssertEqual(Rows.settled(.module("disk"), enabled: ["other"]), .general,
                       "a module switched off under the person stays selected: the pane shows a page no row leads to")
    }

    func testAModuleThatIsOnStaysSelected() {
        // Chosen: `settled` takes no layout, so an id that is on stays selected whether or not a section holds it.
        XCTAssertEqual(Rows.settled(.module("disk"), enabled: ["disk"]), .module("disk"))
    }

    func testTheSettingsSelectionsAreReturnedUnchangedWhateverIsOn() {
        for enabled in [[], ["disk"]] as [Set<String>] {
            XCTAssertEqual(Rows.settled(.general, enabled: enabled), .general)
            XCTAssertEqual(Rows.settled(.about, enabled: enabled), .about)
            XCTAssertEqual(Rows.settled(.log, enabled: enabled), .log)
        }
    }
}
