import XCTest
import AppKit
import HelmUI
import Module_Layout_UI
@testable import HelmApp

/// **Keyboard's page has two shapes, and the harness measures the other one.**
///
/// On a first visit the page draws the tour and holds back the three switches
/// and the try-it field the tour is already showing — the same controls twice,
/// a card apart, was what it did before, and the two copies did not move
/// together. Afterwards it draws all of them and the tour becomes a button.
///
/// An empty store is a first visit, so before `ModulePageRender.pastFirstRun`
/// every measurement in `HelmAppTests` was taken over the introduction rather
/// than over the module: the ratchets recorded 158 layers and fourteen switches
/// from a page that had no tour yet, then read 157 and eleven the day it grew
/// one. Seeding `introSeen` puts them back on the page a person actually lives
/// with.
///
/// **That leaves the first visit measured by nobody, which is this file.** The
/// shape everyone meets once should not be the shape nothing checks.
@MainActor
final class TheFirstVisitDrawsTheTourTests: XCTestCase {

    /// A first visit draws *fewer* controls than the settled page, and that is
    /// the whole point — but not zero, and not the same. Both numbers are read
    /// from the same harness in one test so neither can drift alone.
    func testTheTourReplacesTheSwitchesRatherThanJoiningThem() {
        let first = ModulePageRender.page(for: LayoutDescriptor(), in: .aqua, width: 744,
                                          seededBy: { _, _ in })
        let settled = ModulePageRender.page(for: LayoutDescriptor(), in: .aqua, width: 744)

        // Its own floor: `ModulePageRender.floors` records the settled page,
        // and the first visit is a *smaller* screen on purpose. 100 is well
        // under the 157 measured here and well over «nothing rendered at all»,
        // which is the failure this call exists to separate from a real drop.
        first.assertItDrewSomething(atLeast: 100)
        settled.assertItDrewSomething()

        let firstSwitches = first.controls.filter { $0.name.contains("Switch") }.count
        let settledSwitches = settled.controls.filter { $0.name.contains("Switch") }.count

        XCTAssertGreaterThan(firstSwitches, 0,
                             "the tour draws no switches at all — step three is the three "
                             + "switches themselves, and agreeing with it is switching one on")
        XCTAssertLessThan(firstSwitches, settledSwitches, """
            the first visit draws \(firstSwitches) switches and the settled page \
            \(settledSwitches): the page is drawing its own copies underneath the tour again, \
            which is the duplication — two «Fix as I type» a card apart, each mirroring the \
            store into its own @State, moving separately
            """)
    }

    /// And the tour goes away for good once it has been walked, so the settled
    /// page is not just «the same page with a flag».
    func testTheSettledPageIsNotStillTheTour() {
        let settled = ModulePageRender.page(for: LayoutDescriptor(), in: .aqua, width: 744)
        settled.assertItDrewSomething()
        let first = ModulePageRender.page(for: LayoutDescriptor(), in: .aqua, width: 744,
                                          seededBy: { _, _ in })
        XCTAssertNotEqual(settled.layers.count, first.layers.count,
                          "the two shapes draw the same number of layers, so `introSeen` is "
                          + "reaching nothing and every measurement is of one state")
    }
}
