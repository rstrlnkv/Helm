import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **A keystroke in Hosts' SSH text editor mounts no measuring switcher.**
/// Guards the cache in `SettingsToolbar.segmentedReserveWidth(_:)`
/// (`segmentedReserveCache`, keyed on the options' glyphs in order): a
/// `.segmented` entry's reserve is measured once per set of glyphs, and a
/// declare that repeats a set it has already measured measures nothing.
///
/// Written as a repro (tester, 2026-09-25) against the tree before that
/// cache. `segmentedReserveWidth(_:)` measured the reserve through
/// `SwitcherMeasurementRig` — a fresh `NSHostingView`, a fresh `NSToolbar` on
/// the rig's window and a full layout — and it is called from
/// `actionEntries(for:)`, which `patchActions(_:animated:)` runs on every
/// declare. Hosts' page observes `HostsViewModel`, so every published change
/// re-declares: each character typed into the SSH config
/// (`HostsViewModel.setSSHText(_:)`) reached the toolbar as a declare and
/// took one rig measurement, synchronously, inside the page's own SwiftUI
/// update. Measured then on this Mac, debug build: one measurement per
/// keystroke, 20 of 20; 100 declares of one unchanged `.segmented` entry cost
/// 1828–1990 ms against 1.7 ms for the same declares without it, and 44.8 MB
/// of heap in use before the run loop turned. The reserve it recomputed could
/// not have moved: nothing a keystroke changes is anything an `.icons`
/// switcher draws. Before that pass the reserve was read in the capsule's
/// body, which `HelmToolbarActionsModel.setDeclared(_:)`'s equality guard kept
/// from re-running on an unchanged declaration. Seen red again (tester,
/// 2026-09-26) with the cache read taken out of the tree it guards: 10
/// measurements for 10 keystrokes.
///
/// The subject before the absence: the keystrokes are first shown to reach
/// the toolbar as declarations, or "no measurement" would only mean nothing
/// was declared. Read synchronously — the fold prediction's own one
/// measurement, taken only on a `TabsWidthKey` miss, runs from a settle the
/// run loop schedules later, and is not what this counts;
/// `AKeystrokeInHostsSettlesWithoutMeasuringTheTabsTests` counts that.
@MainActor
final class AKeystrokeInHostsMountsNoMeasuringSwitcherTests: XCTestCase {

    private final class Mute: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    private final class Count { var value = 0 }

    func testTypingIntoTheSSHConfigTakesNoSwitcherMeasurement() throws {
        let vm = ModuleViewModel(transport: Mute())
        let hosts = LivePageToolbarFixture(HostsSettingsPage(vm: vm),
                                           selection: .module(HostsDescriptor.id.rawValue),
                                           width: 1060, height: 700)
        // Dropped on every way out of this body, thrown or returned — a
        // teardown override here is nonisolated and warned three times.
        defer { hosts.drop() }
        hosts.settle(30)
        let onKeys = try XCTUnwrap(hosts.channel.content(for: HostsDescriptor.id.rawValue),
                                   "Hosts declared nothing onto the channel")
        try XCTUnwrap(onKeys.selectedTab, "Hosts declared no tabs").wrappedValue = "ssh"
        hosts.settle(30)
        let onSSH = try XCTUnwrap(hosts.channel.content(for: HostsDescriptor.id.rawValue))
        let viewMode = try XCTUnwrap(onSSH.actions.first { $0.id == "viewMode" }, "Hosts declared no viewMode")
        guard case .segmented(_, let mode) = viewMode.kind else {
            return XCTFail("precondition: Hosts' viewMode is not a .segmented action")
        }
        mode.wrappedValue = "text"
        hosts.settle(30)
        XCTAssertFalse(hosts.mount.host.everyView(ofType: NSTextView.self).isEmpty,
                       "precondition: the SSH tab shows no text editor to type into")

        let redeclares = Count()
        let forward = hosts.channel.onChange
        hosts.channel.onChange = { redeclares.value += 1; forward?() }
        let hvm = HostsViewModel.shared(vm: vm)
        let before = SettingsToolbar.measurementsTaken
        let keystrokes = 10
        var typed = "Host example"
        for index in 0..<keystrokes {
            typed += "\(index % 10)"
            hvm.setSSHText(typed + "\n")
            hosts.mount.host.layoutSubtreeIfNeeded()
        }
        let measured = SettingsToolbar.measurementsTaken - before

        XCTAssertGreaterThanOrEqual(redeclares.value, keystrokes, """
            precondition: \(redeclares.value) declaration(s) reached the toolbar for \(keystrokes) keystrokes — \
            nothing below is about typing
            """)
        XCTAssertEqual(measured, 0, """
            \(keystrokes) keystrokes in Hosts' SSH text editor mounted \(measured) measuring switcher(s) \
            through SwitcherMeasurementRig — each is a hosting view, a toolbar and a layout on the main \
            thread, for a reserve nothing typed can change
            """)
    }
}
