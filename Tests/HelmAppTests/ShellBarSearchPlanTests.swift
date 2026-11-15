import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **What a Flat bar's search does at each room, and what the Flat bar holds in place of the glass item.**
///
/// The plan rows are pure (`ShellBarLayout.searchPlan`) and hold the plan's claims only: the magnifier first (the
/// field 283 to 120, then the 36-point magnifier, the tabs fold only if they still do not fit beside the
/// magnifier); a press or a query in the field holds it at 120 or more with the tabs folded for it. No row feeds
/// the plan the room a shown bar reads, so none says the shown bar keeps that order. The structure row reads
/// a real Flat bar: its toolbar holds no `NSSearchToolbarItem`, its search item is borderless with a plate whose
/// one `NSSearchField` is not bezeled, keeps no recents and says its name. Seen on a shown window (build 1701, by
/// hand, no test): no glass in either look, the 36-point magnifier under Always Collapse Search, a press opening
/// the field to 283 with an editor, the accent ring on the plate's outline, widths 860 to 1060. Not seen: typing,
/// Return, the clear button, the fold at the end of editing, ⌘F, the actions capsule squeezing the field, Reduce
/// Motion, VoiceOver speech, motion.
@MainActor
final class ShellBarSearchPlanTests: XCTestCase {

    private func plan(whole: CGFloat, folded: CGFloat, editing: Bool = false, hasQuery: Bool = false,
                      rests: Bool = false) -> ShellBarLayout.SearchPlan {
        ShellBarLayout.searchPlan(roomWholeTabs: whole, roomFoldedTabs: folded, editing: editing, hasQuery: hasQuery,
                                   alwaysCollapse: rests)
    }

    private func assertPlan(_ got: ShellBarLayout.SearchPlan, folded: Bool, width: CGFloat, collapsed: Bool,
                            _ row: String, line: UInt = #line) {
        XCTAssertEqual(got, ShellBarLayout.SearchPlan(tabsFolded: folded, width: width, collapsed: collapsed),
                       row, line: line)
    }

    func testTheFieldGivesWayBeforeTheTabsDo() {
        assertPlan(plan(whole: 500, folded: 600), folded: false, width: 283, collapsed: false, "ample room")
        assertPlan(plan(whole: 200, folded: 300), folded: false, width: 200, collapsed: false, "field narrows to the room")
        assertPlan(plan(whole: 120, folded: 220), folded: false, width: 120, collapsed: false, "field at its floor")
        assertPlan(plan(whole: 119, folded: 400), folded: false, width: 36, collapsed: true,
                   "under the floor the magnifier, the tabs stay whole")
        assertPlan(plan(whole: 36, folded: 400), folded: false, width: 36, collapsed: true, "magnifier just fits")
    }

    func testTheTabsFoldOnlyWhereTheMagnifierDoesNotFitBesideThem() {
        assertPlan(plan(whole: 35, folded: 300), folded: true, width: 283, collapsed: false,
                   "folded tabs leave the field its room")
        assertPlan(plan(whole: 35, folded: 100), folded: true, width: 36, collapsed: true,
                   "folded tabs leave the magnifier only")
    }

    func testAPressOrAQueryHoldsTheFieldOpenAndFoldsTheTabsForIt() {
        assertPlan(plan(whole: 119, folded: 300, editing: true), folded: true, width: 283, collapsed: false,
                   "editing in a narrow window folds the tabs")
        assertPlan(plan(whole: 119, folded: 150, editing: true), folded: true, width: 150, collapsed: false,
                   "editing takes the folded room")
        assertPlan(plan(whole: 10, folded: 50, editing: true), folded: true, width: 120, collapsed: false,
                   "the floor wins even where it overflows")
        assertPlan(plan(whole: 400, folded: 500, editing: true), folded: false, width: 283, collapsed: false,
                   "editing with room keeps the tabs")
    }

    func testAlwaysCollapseRestsAsTheMagnifierAtAnyRoom() {
        assertPlan(plan(whole: 900, folded: 900, rests: true), folded: false, width: 36, collapsed: true, "resting")
        assertPlan(plan(whole: 10, folded: 900, rests: true), folded: true, width: 36, collapsed: true,
                   "resting never opens the field for the folded room")
    }

    func testARoomThatIsNotANumberReadsAsNone() {
        assertPlan(plan(whole: .nan, folded: .infinity, editing: true), folded: true, width: 120, collapsed: false,
                   "editing")
        assertPlan(plan(whole: .nan, folded: .nan), folded: true, width: 36, collapsed: true, "idle")
    }

    // MARK: - Inputs the first pass did not feed

    /// A room that is a number, and the ones that are not or are below nothing.
    private static let rooms: [CGFloat] = [-.infinity, -50, -0.5, 0, 0.5, 35, 35.999, 36, 36.001, 100, 119, 119.999,
                                           120, 120.001, 200, 282.999, 283, 283.001, 500, 5000, .infinity, .nan]

    /// The editing rule over every pair of rooms: an open field is never the magnifier and never under the floor,
    /// the tabs fold only where the whole tabs leave it less than the floor, and a not-a-number room reads as none.
    func testAnEditingFieldIsNeverTheMagnifierNorNarrowerThanItsFloorAtAnyRoom() {
        for whole in Self.rooms {
            for folded in Self.rooms {
                for rests in [false, true] {
                    let got = plan(whole: whole, folded: folded, editing: true, rests: rests)
                    let row = "editing whole=\(whole) folded=\(folded) rests=\(rests) -> \(got)"
                    XCTAssertFalse(got.collapsed, row)
                    XCTAssertGreaterThanOrEqual(got.width, ShellBarLayout.searchFloor, row)
                    XCTAssertLessThanOrEqual(got.width, ShellBarLayout.searchWidth, row)
                    let usable = whole.isFinite ? whole : 0
                    XCTAssertEqual(got.tabsFolded, usable < ShellBarLayout.searchFloor, row)
                }
            }
        }
    }

    /// Always Collapse Search with an empty, idle field: the magnifier at every width. The tabs fold only where
    /// not even the magnifier fits beside them.
    func testAnIdleRestingSearchIsTheMagnifierAtEveryRoom() {
        for whole in Self.rooms {
            for folded in Self.rooms {
                let got = plan(whole: whole, folded: folded, editing: false, rests: true)
                let row = "resting whole=\(whole) folded=\(folded) -> \(got)"
                XCTAssertTrue(got.collapsed, row)
                XCTAssertEqual(got.width, ShellBarLayout.searchCollapsedWidth, row)
                let usable = whole.isFinite ? whole : 0
                XCTAssertEqual(got.tabsFolded, usable < ShellBarLayout.searchCollapsedWidth, row)
            }
        }
    }

    /// Always Collapse Search with a query left in the field (`hasQuery`, which counts as editing): the field at
    /// every room, wherever the setting. What makes `settleFlat` pass `hasQuery` is
    /// `!flat.field.stringValue.isEmpty`, which no row here reads.
    func testAlwaysCollapseWithAQueryShowsTheFieldAtEveryRoom() {
        for whole in Self.rooms {
            let got = plan(whole: whole, folded: whole, hasQuery: true, rests: true)
            XCTAssertFalse(got.collapsed, "query whole=\(whole) -> \(got)")
        }
    }

    /// The width every plan names, whatever the room: the magnifier's 36 or between the floor and the widest.
    func testNoPlanNamesAWidthBetweenTheMagnifierAndTheFloorNorOutsideTheBounds() {
        for whole in Self.rooms {
            for folded in Self.rooms {
                for editing in [false, true] {
                    for rests in [false, true] {
                        let got = plan(whole: whole, folded: folded, editing: editing, rests: rests)
                        let row = "whole=\(whole) folded=\(folded) editing=\(editing) rests=\(rests) -> \(got)"
                        XCTAssertTrue(got.width.isFinite, row)
                        if got.collapsed {
                            XCTAssertEqual(got.width, ShellBarLayout.searchCollapsedWidth, row)
                        } else {
                            XCTAssertGreaterThanOrEqual(got.width, ShellBarLayout.searchFloor, row)
                            XCTAssertLessThanOrEqual(got.width, ShellBarLayout.searchWidth, row)
                        }
                    }
                }
            }
        }
    }

    /// The edges themselves, one point either side: 36 (the magnifier) and 120 (the field's floor).
    func testTheBoundariesAtExactly36And120() {
        // Idle, tabs whole.
        assertPlan(plan(whole: 36, folded: 36), folded: false, width: 36, collapsed: true, "idle at exactly 36")
        assertPlan(plan(whole: 35.999, folded: 35.999), folded: true, width: 36, collapsed: true, "idle just under 36")
        assertPlan(plan(whole: 120, folded: 120), folded: false, width: 120, collapsed: false, "idle at exactly 120")
        assertPlan(plan(whole: 119.999, folded: 119.999), folded: false, width: 36, collapsed: true,
                   "idle just under 120")
        // Idle, only the folded tabs leave the floor.
        assertPlan(plan(whole: 35, folded: 120), folded: true, width: 120, collapsed: false, "folded at exactly 120")
        assertPlan(plan(whole: 35, folded: 119.999), folded: true, width: 36, collapsed: true, "folded just under 120")
        // Editing.
        assertPlan(plan(whole: 120, folded: 0, editing: true), folded: false, width: 120, collapsed: false,
                   "editing at exactly 120 keeps the tabs")
        assertPlan(plan(whole: 119.999, folded: 0, editing: true), folded: true, width: 120, collapsed: false,
                   "editing just under 120 folds the tabs")
        assertPlan(plan(whole: 36, folded: 36, editing: true), folded: true, width: 120, collapsed: false,
                   "editing at 36 is not the magnifier")
        // The widest.
        assertPlan(plan(whole: 283, folded: 0), folded: false, width: 283, collapsed: false, "exactly the widest")
        assertPlan(plan(whole: 283.001, folded: 0), folded: false, width: 283, collapsed: false, "past the widest")
    }

    /// **Not a number, infinite or below nothing reads as no room**, in each position (documented in the plan's
    /// header). Infinite reads as none too, so the tabs fold rather than the field being given an unbounded room.
    func testRoomsThatAreNotUsableReadAsNoneInEachPosition() {
        for bad in [CGFloat.nan, .infinity, -.infinity, -1, -1000] {
            assertPlan(plan(whole: bad, folded: 300), folded: true, width: 283, collapsed: false, "whole \(bad)")
            assertPlan(plan(whole: bad, folded: bad), folded: true, width: 36, collapsed: true, "both \(bad)")
            assertPlan(plan(whole: 300, folded: bad), folded: false, width: 283, collapsed: false, "folded \(bad)")
            assertPlan(plan(whole: bad, folded: bad, editing: true), folded: true, width: 120, collapsed: false,
                       "editing, both \(bad)")
        }
    }

    // MARK: - The controller

    /// **Rapid open, close, open.** A close's completion that arrives after a newer open has begun must not
    /// hide the field it opened (`ShellBarSearch.generation`). The plate sits in a window that is never shown;
    /// the animation runs on the run loop there, which is proved before the claim is read (`isAnimating`).
    func testAnOpenAfterACloseIsNotUndoneByTheClosesCompletion() throws {
        try XCTSkipIf(HelmMotion.reduceMotion, "Reduce Motion is on, so every width change is a cut")
        let flat = ShellBarSearch(identifier: .init("helm.search.test"), isActive: true, titlebarIsTransparent: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.contentView?.addSubview(flat.plate)
        NSLayoutConstraint.activate([flat.plate.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
                                     flat.plate.topAnchor.constraint(equalTo: window.contentView!.topAnchor)])
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var completions: [String] = []
        // Start at the floor, so the open below is a different width from where the close begins and animates.
        flat.apply(width: 120, collapsed: false, animated: false)

        flat.apply(width: 36, collapsed: true, animated: true) { completions.append("close") }
        XCTAssertTrue(flat.isAnimating, "the close did not animate, so there is no completion to arrive late")
        flat.apply(width: 283, collapsed: false, animated: true) { completions.append("open") }
        XCTAssertTrue(flat.isAnimating, "the open did not animate, so the close's completion is not the one at stake")

        let deadline = Date().addingTimeInterval(HelmMotion.interfaceDuration * 4 + 1)
        while flat.isAnimating, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        for _ in 0..<10 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }

        XCTAssertFalse(flat.isAnimating, "the animation never finished")
        XCTAssertEqual(completions, ["open"], "a stale completion ran, or the last one did not")
        XCTAssertFalse(flat.field.isHidden, "the late close hid the field the second open had shown")
        XCTAssertTrue(flat.magnifier.isHidden, "the magnifier is shown over an open field")
        XCTAssertEqual(flat.target?.width, 283)
        XCTAssertEqual(flat.target?.collapsed, false)
        XCTAssertEqual(Self.widthConstraint(of: flat)?.constant ?? -1, 283, accuracy: 0.5,
                       "the plate settled at its close's width under an open field")
    }

    /// The one width constraint the plate carries (`ShellBarSearch.widthConstraint` is private).
    private static func widthConstraint(of flat: ShellBarSearch) -> NSLayoutConstraint? {
        flat.plate.constraints.first { $0.firstAttribute == .width && $0.secondItem == nil }
    }

    /// A close taken back before it has moved a point: the open asks for the width the close started from.
    func testACloseTakenBackAtOnceDoesNotLeaveThePlateShrinking() throws {
        try XCTSkipIf(HelmMotion.reduceMotion, "Reduce Motion is on, so every width change is a cut")
        let flat = ShellBarSearch(identifier: .init("helm.search.test3"), isActive: true, titlebarIsTransparent: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.contentView?.addSubview(flat.plate)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        flat.apply(width: 36, collapsed: true, animated: true)
        flat.apply(width: 283, collapsed: false, animated: true)
        let deadline = Date().addingTimeInterval(HelmMotion.interfaceDuration * 4 + 1)
        while flat.isAnimating, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        for _ in 0..<20 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(Self.widthConstraint(of: flat)?.constant ?? -1, 283, accuracy: 0.5,
                       "the first close kept shrinking the plate under the open")
        XCTAssertFalse(flat.field.isHidden)
        XCTAssertTrue(flat.magnifier.isHidden)
    }

    /// The same, as many times as a finger can: a hundred alternating requests, the last one wins.
    func testAHundredAlternatingRequestsEndOnTheLastOne() throws {
        let flat = ShellBarSearch(identifier: .init("helm.search.test2"), isActive: true, titlebarIsTransparent: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.contentView?.addSubview(flat.plate)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var ran: [Int] = []
        for i in 0..<100 {
            let close = i % 2 == 0
            flat.apply(width: close ? 36 : 283, collapsed: close, animated: true) { ran.append(i) }
        }
        let deadline = Date().addingTimeInterval(HelmMotion.interfaceDuration * 4 + 1)
        while flat.isAnimating, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        for _ in 0..<10 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertFalse(flat.isAnimating)
        XCTAssertEqual(ran.last, 99, "the last request's completion did not run last: \(ran.suffix(5))")
        XCTAssertFalse(flat.field.isHidden)
        XCTAssertTrue(flat.magnifier.isHidden)
        XCTAssertEqual(Self.widthConstraint(of: flat)?.constant ?? -1, 283, accuracy: 0.5,
                       "the plate settled at a width the last request did not ask for")
    }

    func testAFlatBarHoldsNoGlassSearchItem() throws {
        PinnedBarSettings.pin(in: self, look: .flat)
        let fixture = LivePageInTheToolbarFixture(
            Text("the list").frame(maxWidth: .infinity, maxHeight: .infinity)
                .helmWindowToolbar(HelmPageToolbarContent(search: HelmToolbarSearch(
                    prompt: "Search", text: .constant(""), onSubmit: {})), token: "test.flatSearch"),
            selection: .module("test.flatSearch"), width: 1060, height: 400)
        defer { fixture.drop() }
        fixture.settle(20)

        let items = try XCTUnwrap(fixture.mount.window?.toolbar?.items)
        XCTAssertFalse(items.contains { $0 is NSSearchToolbarItem }, "a Flat bar lists an NSSearchToolbarItem")
        let item = try XCTUnwrap(items.first { $0.itemIdentifier.rawValue == "helm.search" },
                                 "the Flat bar lists no search item at all")
        XCTAssertFalse(item.isBordered)
        let plate = try XCTUnwrap(item.view as? ShellBarPlate, "the search item's view is not a ShellBarPlate")
        let fields = plate.everyView(ofType: NSSearchField.self)
        XCTAssertEqual(fields.count, 1)
        let field = try XCTUnwrap(fields.first)
        XCTAssertFalse(field.isBezeled)
        XCTAssertNil(field.recentsAutosaveName)
        XCTAssertEqual(field.recentSearches, [])
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField)
        XCTAssertTrue(fixture.searchField === field, "the test support does not find the Flat field")
    }
}
