import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// REPRO (tester, 2026-09-26) — red on the working tree it was written
/// against; green since `PageBar.tabsWidth` keeps the centre tabs' width
/// under `SettingsToolbar.TabsWidthKey` (engineer, 2026-09-26), and kept as
/// the guard on it.
///
/// **A pause after a keystroke in Hosts' SSH text editor measured the centre
/// tabs again, although nothing a keystroke can move had moved.** The
/// brother of `AKeystrokeInHostsMountsNoMeasuringSwitcherTests`, one step
/// later: that file counts what a keystroke measures synchronously, inside
/// the declare, and says outright that the fold prediction's own one
/// measurement, taken only on a `TabsWidthKey` miss, "runs from a settle
/// the run loop schedules later, and is not what this counts". This
/// counts it. Every declare reaches
/// `SettingsToolbar.show(_:key:)`, which re-arms `scheduleSettle(_:)`
/// "whether or not the bar actually changed", and `settleInterval` (0.1 s)
/// after the last keystroke `settle(_:)` runs. When this was written it
/// asked a `switcherWidths` method for two widths, compact and full — two
/// `SwitcherMeasurementRig` mounts, each a hosting view, a toolbar and a
/// layout, for Keys / SSH hosts, whose titles, glyphs, style, language and
/// selection a keystroke cannot move. Measured on this Mac, debug build, ten
/// keystrokes 0.2 s apart (a person typing at five characters a second): 20
/// measurements, two per keystroke, in two runs out of two; the run-loop
/// turn that carried each settle took 66–79 ms against at most 12 ms for
/// every other turn in the same loop. Typed 0.05 s apart the timer is
/// re-armed before it fires and the burst costs 2. Present at HEAD then —
/// it is the same input, a keystroke on Hosts, reaching the other
/// measurement. Now `settle(_:)` asks `switcherWidth(tabs:style:selectedID:)`
/// for the full width alone, and only when `TabsWidthKey` misses: 10 for 10
/// keystrokes with the key's read taken out (engineer), 0 with it.
///
/// This file proves the miss that must *not* happen; which misses must, one
/// field of the key at a time, is
/// `TheTabsAreMeasuredAgainOnlyWhenWhatTheyDrawMovesTests`.
///
/// The subject before the absence, twice: the keystrokes are first shown to
/// reach the toolbar as declarations, each followed by a rest longer than
/// `SettingsToolbar.settleInterval` by the clock, so a settle was due after
/// every one; and after the keystrokes, tabs this process has never drawn —
/// Hosts' own titles with a fresh suffix, which no cache of widths however
/// keyed can already hold — are declared onto the same bar and the settle
/// that follows is shown to reach the counter, so a zero below is not an
/// instrument that cannot see a settle's measurement.
@MainActor
final class AKeystrokeInHostsSettlesWithoutMeasuringTheTabsTests: XCTestCase {

    private final class Mute: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    private final class Count { var value = 0 }

    /// Turns the run loop for `seconds` by the clock — `settle(_:)` runs from
    /// a timer, and a turn that returns on the first source it serves buys no
    /// time.
    private func rest(_ seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }

    func testAPauseAfterTypingIntoTheSSHConfigMeasuresNoTabs() throws {
        // Raw, so a key the domain did not hold is removed again rather than
        // written back as the typed getter's default.
        let store = AppSettings.store
        let found = store.object(ToolbarSwitcherStyle.storageKey)
        addTeardownBlock { @MainActor in
            store.set(found, for: ToolbarSwitcherStyle.storageKey)
            NotificationCenter.default.post(name: .helmToolbarSwitcherStyleChanged, object: nil)
        }
        AppSettings.toolbarSwitcherStyle = .text
        let vm = ModuleViewModel(transport: Mute())
        let hosts = LivePageToolbarFixture(HostsSettingsPage(vm: vm),
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
        rest(4 * SettingsToolbar.settleInterval)

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
            rest(pause)
        }
        rest(2 * SettingsToolbar.settleInterval)
        let measured = SettingsToolbar.measurementsTaken - before

        XCTAssertGreaterThanOrEqual(redeclares.value, keystrokes, """
            precondition: \(redeclares.value) declaration(s) reached the toolbar for \(keystrokes) keystrokes — \
            nothing below is about typing
            """)

        // The instrument: tabs this process has never drawn — titles no
        // cache, however keyed, can already hold — declared onto the same
        // bar, and the settle that follows is seen measuring them.
        let unseen = UUID().uuidString.prefix(8)
        let beforeControl = SettingsToolbar.measurementsTaken
        hosts.channel.declare(HelmPageToolbarContent(
            tabs: onSSH.tabs.map { HelmToolbarTab(id: $0.id, title: "\($0.title) \(unseen)", symbol: $0.symbol) },
            selectedTab: onSSH.selectedTab, actions: onSSH.actions),
            token: HostsDescriptor.id.rawValue, generation: hosts.channel.nextGeneration())
        rest(4 * SettingsToolbar.settleInterval)
        XCTAssertGreaterThan(SettingsToolbar.measurementsTaken - beforeControl, 0, """
            precondition: tabs never drawn before, declared onto the same bar, took no measurement either — \
            the count below cannot see a settle's measurement at all
            """)

        XCTAssertEqual(measured, 0, """
            \(keystrokes) keystrokes in Hosts' SSH text editor, each followed by \(pause) s, mounted \
            \(measured) measuring switcher(s) through SwitcherMeasurementRig from the settle that follows \
            each one — the centre tabs' widths, for tabs a keystroke cannot change
            """)
    }
}
