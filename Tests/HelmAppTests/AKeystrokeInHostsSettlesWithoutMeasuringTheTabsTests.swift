import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **A pause after a keystroke in Hosts' SSH text editor measures the centre tabs no more than the keystroke
/// did, and draws them no more, although nothing a keystroke can move has moved.** The tabs zone
/// (`ShellBarTabs`) reads both of its natural widths when a show carries a new shape, and counts that in
/// `measureCount`; it re-roots its hosts when a show carries a drawing other than the one it drew, and
/// counts that in `redrawCount`; a show equal to the last does neither. Hosts' two tabs (Keys, SSH hosts)
/// are the same words, glyphs, style and selection under every character typed into the SSH config.
///
/// The brother of `AKeystrokeInHostsMountsNoMeasuringSwitcherTests`, which counts the actions zone's reserve
/// across the same keystrokes with no pause. Here each keystroke is followed by a rest by the clock and a
/// layout of the bar, so a measurement or a redraw that the bar schedules after a declaration, or that a
/// layout pass starts, is counted too. Which changes of the tabs must be measured, one field at a time, is
/// `TheTabsAreMeasuredAgainOnlyWhenWhatTheyDrawMovesTests`.
///
/// The subject before the absence, twice: the keystrokes are first shown to reach the page (the editor holds
/// what was typed) and the bar (a declaration reached its handler for each); and after them, tabs this
/// process has never drawn — Hosts' own titles with a fresh suffix — are declared onto the same bar and are
/// seen to move both counters, so a zero below is not a counter that cannot see a measurement.
@MainActor
final class AKeystrokeInHostsSettlesWithoutMeasuringTheTabsTests: XCTestCase {

    func testAPauseAfterTypingIntoTheSSHConfigMeasuresNoTabs() throws {
        PinnedBarSettings.pin(in: self)
        let rig = try HostsSSHEditorRig.make()
        defer { rig.drop() }
        let tabs = rig.fixture.pageBar.tabs
        XCTAssertGreaterThan(tabs.measureCount, 0, "precondition: Hosts' tabs were never measured on this bar")
        XCTAssertFalse(rig.declared.tabs.isEmpty, "precondition: Hosts declared no centre tabs")
        // Whatever the tab and mode changes above started has run.
        PinnedBarSettings.rest(0.3)
        rig.fixture.settle(5)

        let measuresBefore = tabs.measureCount
        let redrawsBefore = tabs.redrawCount
        let pause = 0.2
        let keystrokes = 10
        for _ in 0..<keystrokes {
            rig.keystroke()
            rig.fixture.pageBar.layout()
            PinnedBarSettings.rest(pause)
        }
        rig.fixture.settle(5)
        let measured = tabs.measureCount - measuresBefore
        let redrawn = tabs.redrawCount - redrawsBefore

        XCTAssertGreaterThanOrEqual(rig.redeclares.value, keystrokes, """
            precondition: \(rig.redeclares.value) declaration(s) reached the bar for \(keystrokes) keystrokes — \
            nothing below is about typing
            """)
        XCTAssertTrue(rig.editorHoldsWhatWasTyped, "precondition: the editor does not hold what was typed")
        XCTAssertEqual(rig.fixture.bar.presentation,
                       .page(key: HostsDescriptor.id.rawValue, isLive: true, isDimmed: false),
                       "precondition: the bar does not show Hosts' page live")

        // The instrument: tabs this process has never drawn, declared onto the same bar.
        let unseen = UUID().uuidString.prefix(8)
        rig.fixture.channel.declare(HelmPageToolbarContent(
            tabs: rig.declared.tabs.map { HelmToolbarTab(id: $0.id, title: "\($0.title) \(unseen)", symbol: $0.symbol) },
            selectedTab: rig.declared.selectedTab, actions: rig.declared.actions),
            token: HostsDescriptor.id.rawValue, generation: rig.fixture.channel.nextGeneration())
        rig.fixture.settle(5)
        XCTAssertEqual(tabs.measureCount - measuresBefore - measured, 1, """
            precondition: tabs never drawn before, declared onto the same bar, were not measured once — the \
            count below cannot see a measurement at all
            """)
        XCTAssertEqual(tabs.redrawCount - redrawsBefore - redrawn, 1, """
            precondition: tabs never drawn before were not redrawn once — the count below cannot see a redraw
            """)

        XCTAssertEqual(measured, 0, """
            \(keystrokes) keystrokes in Hosts' SSH text editor, each followed by \(pause) s and a layout of the \
            bar, measured the centre tabs \(measured) time(s) — tabs a keystroke cannot change
            """)
        XCTAssertEqual(redrawn, 0, """
            \(keystrokes) keystrokes in Hosts' SSH text editor re-rooted the centre tabs' hosts \(redrawn) \
            time(s) — the tabs a keystroke cannot change
            """)
    }
}
