import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **A pause after a keystroke in Hosts' SSH text editor measures the centre
/// tabs no more than before, since nothing a keystroke can move has moved.** The
/// brother of `AKeystrokeInHostsMountsNoMeasuringSwitcherTests`, one step
/// later: that file counts what a keystroke measures synchronously, inside
/// the declare, and says outright that the fold prediction's own one
/// measurement, taken only on a `TabsWidthKey` miss, "runs from a settle
/// the run loop schedules later, and is not what this counts". This
/// counts it. Every declare reaches
/// `SettingsToolbar.show(_:key:)`, which re-arms `scheduleSettle(_:)`
/// "whether or not the bar actually changed", and `settleInterval` (0.1 s)
/// after the last keystroke `settle(_:)` runs. It asks
/// `wholeTabsWidth(_:_:)` for the tabs' full width, and that calls
/// `switcherWidth(tabs:style:look:selectedID:)` — a `SwitcherMeasurementRig`
/// mount, a hosting view, a toolbar and a layout — only when
/// `PageBar.tabsWidth` does not hold a width under the same `TabsWidthKey`.
/// The tabs of Keys / SSH hosts have titles, glyphs, style, language and
/// selection that a keystroke cannot move.
///
/// **What the row holds.** The line of `wholeTabsWidth(_:_:)` that returns the
/// kept width when its key matches. With that line taken out the count below
/// prints 10 measuring switchers for the 10 keystrokes, under both looks.
///
/// This file proves the miss that must *not* happen; which misses must, one
/// field of the key at a time, is
/// `TheTabsAreMeasuredAgainOnlyWhenWhatTheyDrawMovesTests`.
///
/// The subject before the absence, twice: the keystrokes are first shown to
/// reach the toolbar as declarations and the page (the editor holds what was
/// typed), each followed by a rest longer than
/// `SettingsToolbar.settleInterval` by the clock, so a settle was due after
/// every one; and after the keystrokes, tabs this process has never drawn —
/// Hosts' own titles with a fresh suffix, which no cache of widths however
/// keyed can already hold — are declared onto the same bar and the settle
/// that follows is shown to reach the counter, so a zero below is not an
/// instrument that cannot see a settle's measurement.
///
/// **The bar.** A `SettingsToolbar` built with the default lead
/// `.sidebarSeparator` in a `MountedRender` window
/// (`LivePageInTheToolbarFixture`), not the `lead: .spacer` bar the app's
/// window builds. The count is the toolbar's own
/// (`SettingsToolbar.measurementsTaken`), not Helm's page bar's
/// `ShellBarTabs.measureCount`.
///
/// **The look.** The tabs are measured in the look's cell, and the look is
/// read when a bar is built (`AppSettings.barAppearance`), so the row is one
/// test per look, with the settings the bar reads pinned first
/// (`PinnedBarSettings`).
@MainActor
final class AKeystrokeInHostsSettlesWithoutMeasuringTheTabsTests: XCTestCase {

    private final class Mute: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    private final class Count { var value = 0 }

    func testAPauseAfterTypingIntoTheSSHConfigMeasuresNoTabsUnderFlat() throws {
        try pauseAfterTyping(under: .flat)
    }

    func testAPauseAfterTypingIntoTheSSHConfigMeasuresNoTabsUnderLiquidGlass() throws {
        try pauseAfterTyping(under: .liquidGlass)
    }

    private func pauseAfterTyping(under look: HelmBarAppearance) throws {
        PinnedBarSettings.pin(in: self)
        AppSettings.barAppearance = look
        let vm = ModuleViewModel(transport: Mute())
        let hosts = LivePageInTheToolbarFixture(HostsSettingsPage(vm: vm),
                                                selection: .module(HostsDescriptor.id.rawValue),
                                                width: 1060, height: 700)
        defer { hosts.drop() }
        hosts.settle(30)
        let onKeys = try XCTUnwrap(hosts.channel.content(for: HostsDescriptor.id.rawValue),
                                   "Hosts declared nothing onto the channel")
        try XCTUnwrap(onKeys.selectedTab, "Hosts declared no tabs").wrappedValue = "ssh"
        hosts.settle(30)
        let onSSH = try XCTUnwrap(hosts.channel.content(for: HostsDescriptor.id.rawValue))
        XCTAssertFalse(onSSH.tabs.isEmpty, "precondition: Hosts declared no centre tabs, so nothing settles on them")
        let viewMode = try XCTUnwrap(onSSH.actions.first { $0.id == "viewMode" }, "Hosts declared no viewMode")
        guard case .segmented(_, let mode) = viewMode.kind else {
            return XCTFail("precondition: Hosts' viewMode is not a .segmented action")
        }
        mode.wrappedValue = "text"
        hosts.settle(30)
        XCTAssertFalse(hosts.mount.host.everyView(ofType: NSTextView.self).isEmpty,
                       "precondition: the SSH tab shows no text editor to type into")
        // Whatever the tab and mode changes above scheduled has run.
        PinnedBarSettings.rest(4 * SettingsToolbar.settleInterval)

        let redeclares = Count()
        let forward = hosts.channel.onChange
        hosts.channel.onChange = { redeclares.value += 1; forward?() }
        let hvm = HostsViewModel.shared(vm: vm)
        let pause = 2 * SettingsToolbar.settleInterval
        let keystrokes = 10
        let before = SettingsToolbar.measurementsTaken
        var typed = "Host example"
        for index in 0..<keystrokes {
            typed += "\(index % 10)"
            hvm.setSSHText(typed + "\n")
            hosts.mount.host.layoutSubtreeIfNeeded()
            PinnedBarSettings.rest(pause)
        }
        PinnedBarSettings.rest(2 * SettingsToolbar.settleInterval)
        let measured = SettingsToolbar.measurementsTaken - before

        XCTAssertGreaterThanOrEqual(redeclares.value, keystrokes, """
            \(look): precondition: \(redeclares.value) declaration(s) reached the toolbar for \(keystrokes) \
            keystrokes — nothing below is about typing
            """)
        XCTAssertTrue(hosts.mount.host.everyView(ofType: NSTextView.self).contains { $0.string.contains(typed) },
                      "\(look): precondition: the editor does not hold what was typed")

        // The instrument: tabs this process has never drawn — titles no
        // cache, however keyed, can already hold — declared onto the same
        // bar, and the settle that follows is seen measuring them.
        let unseen = UUID().uuidString.prefix(8)
        let beforeControl = SettingsToolbar.measurementsTaken
        hosts.channel.declare(HelmPageToolbarContent(
            tabs: onSSH.tabs.map { HelmToolbarTab(id: $0.id, title: "\($0.title) \(unseen)", symbol: $0.symbol) },
            selectedTab: onSSH.selectedTab, actions: onSSH.actions),
            token: HostsDescriptor.id.rawValue, generation: hosts.channel.nextGeneration())
        PinnedBarSettings.rest(4 * SettingsToolbar.settleInterval)
        XCTAssertGreaterThan(SettingsToolbar.measurementsTaken - beforeControl, 0, """
            \(look): precondition: tabs never drawn before, declared onto the same bar, took no measurement \
            either — the count below cannot see a settle's measurement at all
            """)

        XCTAssertEqual(measured, 0, """
            \(look): \(keystrokes) keystrokes in Hosts' SSH text editor, each followed by \(pause) s, mounted \
            \(measured) measuring switcher(s) through SwitcherMeasurementRig from the settle that follows \
            each one — the centre tabs' widths, for tabs a keystroke cannot change
            """)
    }
}
