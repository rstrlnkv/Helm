import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **What `HostsSettingsPage` declares onto the window's own toolbar — read
/// off `HelmWindowToolbarChannel`, never off a rendered `NSToolbar`.**
///
/// `SettingsToolbar` is `HelmApp`-only (`LivePageToolbarFixture`'s own
/// header), and this module's `UITests` target cannot build one — but the
/// page's declaration itself, `HelmPageToolbarContent`, crosses no such
/// boundary: it reaches this target through the same
/// `HelmWindowToolbarChannel` `MountedRender`'s own `channel:` parameter
/// already wires in. What a live bar draws from a toggle's own tint or a
/// capsule model is `HelmApp`'s to prove (`Tests/HelmAppTests`); this file is
/// about the one fact this page owns outright — what it *says*.
@MainActor
final class TheToolbarDeclarationMatchesWhatThePageOffersTests: XCTestCase {

    private var render: MountedRender?

    override func tearDown() {
        render?.drop()
        render = nil
        super.tearDown()
    }

    private func declaredContent(_ channel: HelmWindowToolbarChannel) -> HelmPageToolbarContent? {
        channel.content(for: HostsDescriptor.id.rawValue)
    }

    /// Mounts the page against a model already past its first load —
    /// `.shared(vm:)` hands the page the very instance this awaited, so the
    /// declaration read straight after `settle` reflects the load rather
    /// than the construction default.
    private func mountPage(_ hosted: HostsUIWire, channel: HelmWindowToolbarChannel) async -> MountedRender {
        let hvm = HostsViewModel.shared(vm: hosted.vm)
        await hvm.firstLoad?.value
        let mounted = MountedRender(HostsSettingsPage(vm: hosted.vm), width: 900, height: 700,
                                    appearance: .aqua, channel: channel)
        mounted.settle(30)
        render = mounted
        return mounted
    }

    /// The id of a `.segmented` action's own current option — `nil` for
    /// anything else, the same shape `isOn(_:)` used to answer for the old
    /// `.toggle` pair.
    private func selected(_ action: HelmToolbarAction) -> String? {
        guard case let .segmented(_, selection) = action.kind else { return nil }
        return selection.wrappedValue
    }

    /// Picks `optionID` the way the control's own action does — writing the
    /// binding, not calling a per-option closure: `.segmented` carries none.
    private func pick(_ optionID: String, in action: HelmToolbarAction) {
        guard case let .segmented(options, selection) = action.kind else {
            XCTFail("\(action.id) is not segmented")
            return
        }
        guard options.contains(where: { $0.id == optionID }) else {
            XCTFail("\(optionID) is not one of \(action.id)'s own options")
            return
        }
        selection.wrappedValue = optionID
    }

    // MARK: - Tabs

    /// **Keys first** — the page's own reason, restated: what brings somebody
    /// here is «what are my keys and which of them still do anything».
    func testTheTwoTabsCarryTheirOwnIdsAndKeysIsSelectedFirst() async throws {
        let hosted = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined)
        let channel = HelmWindowToolbarChannel()
        _ = await mountPage(hosted, channel: channel)

        let declared = try XCTUnwrap(declaredContent(channel))
        XCTAssertEqual(declared.tabs.map(\.id), ["keys", "ssh"])
        let selectedTab = try XCTUnwrap(declared.selectedTab)
        XCTAssertEqual(selectedTab.wrappedValue, "keys", "Keys is the tab a fresh visit opens on")
    }

    // MARK: - New key

    func testNewKeyIsVisibleOnlyOnKeysAndDimmedWhenTheDirectoryCannotBeRead() async throws {
        let hosted = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined,
                                      keys: WireKeys(names: nil))
        let channel = HelmWindowToolbarChannel()
        let mounted = await mountPage(hosted, channel: channel)

        var declared = try XCTUnwrap(declaredContent(channel))
        var newKey = try XCTUnwrap(declared.actions.first { $0.id == "newKey" })
        XCTAssertTrue(newKey.isVisible, "New key must show on the Keys tab")
        XCTAssertFalse(newKey.isEnabled, "New key must be dimmed while ~/.ssh cannot be read")

        let selectedTab = try XCTUnwrap(declared.selectedTab)
        selectedTab.wrappedValue = "ssh"
        mounted.settle(30)

        declared = try XCTUnwrap(declaredContent(channel))
        newKey = try XCTUnwrap(declared.actions.first { $0.id == "newKey" })
        XCTAssertFalse(newKey.isVisible, "New key must not show on the SSH tab")
    }

    func testNewKeyIsEnabledWhenKeysAreReadable() async throws {
        let hosted = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined)
        let channel = HelmWindowToolbarChannel()
        _ = await mountPage(hosted, channel: channel)

        let declared = try XCTUnwrap(declaredContent(channel))
        let newKey = try XCTUnwrap(declared.actions.first { $0.id == "newKey" })
        XCTAssertTrue(newKey.isEnabled, "New key must be enabled once ~/.ssh reads back")
    }

    // MARK: - The view switcher

    /// **The pair is one `.segmented` action in the capsule, styled as a
    /// switcher rather than as two blue-highlighted `.toggle` buttons**
    /// (`HostsSettingsPage.toolbarContent`'s own doc names why: the owner
    /// asked for it on 2026-09-25).
    func testTheViewSwitcherShowsOnlyOnSSHAndPickingTextTurnsItOnAndDrawsTheEditor() async throws {
        let hosted = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined)
        let channel = HelmWindowToolbarChannel()
        let mounted = await mountPage(hosted, channel: channel)

        var declared = try XCTUnwrap(declaredContent(channel))
        var viewMode = try XCTUnwrap(declared.actions.first { $0.id == "viewMode" })
        XCTAssertFalse(viewMode.isVisible, "the view switcher must not show on the Keys tab")

        let selectedTab = try XCTUnwrap(declared.selectedTab)
        selectedTab.wrappedValue = "ssh"
        mounted.settle(30)

        declared = try XCTUnwrap(declaredContent(channel))
        viewMode = try XCTUnwrap(declared.actions.first { $0.id == "viewMode" })
        XCTAssertTrue(viewMode.isVisible, "the view switcher must show on the SSH tab")
        guard case let .segmented(options, _) = viewMode.kind else {
            return XCTFail("viewMode is not segmented")
        }
        XCTAssertEqual(options.map(\.id), ["table", "text"])
        XCTAssertEqual(selected(viewMode), "table", "Table is selected first")
        XCTAssertNil(mounted.host.everyView(ofType: NSTextView.self).first { $0.string.contains("Host a") },
                    "the config's text editor must not be on screen while Table is showing")

        pick("text", in: viewMode)
        mounted.settle(30)

        declared = try XCTUnwrap(declaredContent(channel))
        viewMode = try XCTUnwrap(declared.actions.first { $0.id == "viewMode" })
        XCTAssertEqual(selected(viewMode), "text", "Plain text is selected once picked")
        XCTAssertNotNil(mounted.host.everyView(ofType: NSTextView.self).first { $0.string.contains("Host a") },
                        "the SSH config's text editor must be on screen once Plain text is on")
    }

    func testTheViewSwitcherIsDimmedWhenTheSSHConfigCannotBeRead() async throws {
        let hosted = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined,
                                      sshConfig: UnreadableSSHConfig())
        let channel = HelmWindowToolbarChannel()
        let mounted = await mountPage(hosted, channel: channel)

        let selectedTab = try XCTUnwrap(declaredContent(channel)?.selectedTab)
        selectedTab.wrappedValue = "ssh"
        mounted.settle(30)

        let declared = try XCTUnwrap(declaredContent(channel))
        let viewMode = try XCTUnwrap(declared.actions.first { $0.id == "viewMode" })
        XCTAssertFalse(viewMode.isEnabled, "the view switcher must be dimmed once the SSH config cannot be read")
    }
}
