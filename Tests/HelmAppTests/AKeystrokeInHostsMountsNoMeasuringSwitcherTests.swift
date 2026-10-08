import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **A keystroke in Hosts' SSH text editor mounts no measuring switcher.** Guards the cache in
/// `ShellBarActions.segmentedReserveWidth(_:appearance:)` (`reserveCache`, keyed on the options' glyphs in
/// order and the bar's look): a `.segmented` action's reserve is measured once per set of glyphs, and a
/// declaration that repeats a set it has already measured measures nothing.
///
/// Hosts' page observes `HostsViewModel`, so every published change declares its toolbar again: each
/// character typed into the SSH config (`HostsViewModel.setSSHText(_:)`) reaches the bar's actions zone,
/// which builds its entries on every show, and a reserve measured on every build mounts a hosting view and
/// takes a layout on the main thread for a width nothing typed can change. The count here is
/// `ShellBarActions.reserveMeasurements`, read synchronously across the keystrokes.
/// `AKeystrokeInHostsSettlesWithoutMeasuringTheTabsTests` counts the tabs zone's measurement across the
/// same keystrokes.
///
/// The subject before the absence, twice: the keystrokes are first shown to reach the page (the editor holds
/// what was typed) and the bar (a declaration reached its handler for each), and after them a `.segmented`
/// action with glyphs this process has never measured is declared onto the same bar and is seen taking a
/// measurement, so a zero below is not a counter that cannot see one.
@MainActor
final class AKeystrokeInHostsMountsNoMeasuringSwitcherTests: XCTestCase {

    func testTypingIntoTheSSHConfigTakesNoSwitcherMeasurement() throws {
        PinnedBarSettings.pin(in: self)
        let rig = try HostsSSHEditorRig.make()
        defer { rig.drop() }

        let before = ShellBarActions.reserveMeasurements
        let keystrokes = 10
        for _ in 0..<keystrokes { rig.keystroke() }
        let measured = ShellBarActions.reserveMeasurements - before

        XCTAssertGreaterThanOrEqual(rig.redeclares.value, keystrokes, """
            precondition: \(rig.redeclares.value) declaration(s) reached the bar for \(keystrokes) keystrokes — \
            nothing below is about typing
            """)
        rig.fixture.settle(5)
        XCTAssertTrue(rig.editorHoldsWhatWasTyped, "precondition: the editor does not hold what was typed")
        XCTAssertEqual(rig.fixture.bar.presentation,
                       .page(key: HostsDescriptor.id.rawValue, isLive: true, isDimmed: false),
                       "precondition: the bar does not show Hosts' page live")

        // The instrument: a `.segmented` action no earlier row has measured, declared onto this bar.
        let unseen = HelmToolbarAction(id: "unseenMode", title: "Unseen", isVisible: true, options: [
            HelmToolbarTab(id: "a", title: "A", symbol: "tortoise"),
            HelmToolbarTab(id: "b", title: "B", symbol: "hare"),
            HelmToolbarTab(id: "c", title: "C", symbol: "ant"),
        ], selection: .constant("a"))
        let beforeControl = ShellBarActions.reserveMeasurements
        rig.fixture.channel.declare(
            HelmPageToolbarContent(tabs: rig.declared.tabs, selectedTab: rig.declared.selectedTab,
                                   actions: rig.declared.actions + [unseen]),
            token: HostsDescriptor.id.rawValue, generation: rig.fixture.channel.nextGeneration())
        XCTAssertGreaterThan(ShellBarActions.reserveMeasurements - beforeControl, 0, """
            precondition: a .segmented action never measured before, declared onto the same bar, took no \
            measurement — the count above cannot see one at all
            """)

        XCTAssertEqual(measured, 0, """
            \(keystrokes) keystrokes in Hosts' SSH text editor mounted \(measured) measuring switcher(s) for \
            a reserve nothing typed can change
            """)
    }
}
