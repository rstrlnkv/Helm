import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **A keystroke in Hosts' SSH text editor mounts no measuring switcher.**
/// Holds the cache in `SettingsToolbar.segmentedReserveWidth(_:look:)`
/// (`segmentedReserveCache`, keyed on the options' glyphs in order and the
/// bar's look): a `.segmented` entry's reserve is measured once per set of
/// glyphs, and a declare that repeats a set it has already measured measures
/// nothing.
///
/// Without the cache `segmentedReserveWidth(_:look:)` measures the reserve
/// through `SwitcherMeasurementRig` — a fresh `NSHostingView`, a fresh
/// `NSToolbar` on the rig's window and a full layout — and it is called from
/// `actionEntries(for:look:)`, which `patchActions(_:animated:)` runs on every
/// declare. Hosts' page observes `HostsViewModel`, so every published change
/// re-declares: each character typed into the SSH config
/// (`HostsViewModel.setSSHText(_:)`) reaches the toolbar as a declare.
/// The reserve it would recompute cannot have moved: nothing a keystroke
/// changes is anything an `.icons` switcher draws.
///
/// **What the row holds.** The line of `segmentedReserveWidth(_:look:)` that
/// returns the cached width. With that line taken out the count below is
/// 11 measuring switchers for the 10 keystrokes.
///
/// The subject before the absence, twice: the keystrokes are first shown to
/// reach the toolbar as declarations and the page (the editor holds what was
/// typed), or "no measurement" would only mean nothing was declared; and
/// after them a `.segmented` action with glyphs this process has never
/// measured under that look is declared onto the same bar and is seen taking
/// a measurement, so a zero below is not a counter that cannot see one. Read
/// synchronously — the fold prediction's own one measurement, taken only on a
/// `TabsWidthKey` miss, runs from a settle the run loop schedules later, and
/// is not what this counts; `AKeystrokeInHostsSettlesWithoutMeasuringTheTabsTests`
/// counts that.
///
/// **The bar.** A `SettingsToolbar` built with the default lead
/// `.sidebarSeparator` in a `MountedRender` window
/// (`LivePageInTheToolbarFixture`), not the `lead: .spacer` bar the app's
/// window builds. The count is the toolbar's own
/// (`SettingsToolbar.measurementsTaken`), not Helm's page bar's
/// `ShellBarActions.reserveMeasurements`.
///
/// **The look.** The reserve is measured in the look's cell and the cache is
/// keyed on it, and the look is read when a bar is built
/// (`AppSettings.barAppearance`), so the row is one test per look; the
/// settings the bar reads are pinned (`PinnedBarSettings`) and the look is
/// set after that. The control's glyphs differ per look, because the cache
/// is shared by every bar of the process.
@MainActor
final class AKeystrokeInHostsMountsNoMeasuringSwitcherTests: XCTestCase {

    private final class Mute: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    private final class Count { var value = 0 }

    func testTypingIntoTheSSHConfigTakesNoSwitcherMeasurementUnderFlat() throws {
        try typeIntoTheSSHConfig(under: .flat, unseenGlyphs: ["tortoise", "hare", "ant"])
    }

    func testTypingIntoTheSSHConfigTakesNoSwitcherMeasurementUnderLiquidGlass() throws {
        try typeIntoTheSSHConfig(under: .liquidGlass, unseenGlyphs: ["bird", "fish", "pawprint"])
    }

    private func typeIntoTheSSHConfig(under look: HelmBarAppearance, unseenGlyphs: [String]) throws {
        PinnedBarSettings.pin(in: self)
        AppSettings.barAppearance = look
        let vm = ModuleViewModel(transport: Mute())
        let hosts = LivePageInTheToolbarFixture(HostsSettingsPage(vm: vm),
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
            \(look): precondition: \(redeclares.value) declaration(s) reached the toolbar for \(keystrokes) \
            keystrokes — nothing below is about typing
            """)
        hosts.settle(5)
        XCTAssertTrue(hosts.mount.host.everyView(ofType: NSTextView.self).contains { $0.string.contains(typed) },
                      "\(look): precondition: the editor does not hold what was typed")

        // The instrument: a `.segmented` action no earlier row has measured under this look, declared onto
        // this bar.
        let unseen = HelmToolbarAction(id: "unseenMode", title: "Unseen", isVisible: true,
                                       options: zip(["a", "b", "c"], unseenGlyphs).map {
                                           HelmToolbarTab(id: $0, title: $0.uppercased(), symbol: $1)
                                       }, selection: .constant("a"))
        let beforeControl = SettingsToolbar.measurementsTaken
        hosts.channel.declare(
            HelmPageToolbarContent(tabs: onSSH.tabs, selectedTab: onSSH.selectedTab,
                                   actions: onSSH.actions + [unseen]),
            token: HostsDescriptor.id.rawValue, generation: hosts.channel.nextGeneration())
        PinnedBarSettings.rest(0.4)
        XCTAssertGreaterThan(SettingsToolbar.measurementsTaken - beforeControl, 0, """
            \(look): precondition: a .segmented action never measured before, declared onto the same bar, \
            took no measurement — the count above cannot see one at all
            """)

        XCTAssertEqual(measured, 0, """
            \(look): \(keystrokes) keystrokes in Hosts' SSH text editor mounted \(measured) measuring \
            switcher(s) through SwitcherMeasurementRig — each is a hosting view, a toolbar and a layout on \
            the main thread, for a reserve nothing typed can change
            """)
    }
}
