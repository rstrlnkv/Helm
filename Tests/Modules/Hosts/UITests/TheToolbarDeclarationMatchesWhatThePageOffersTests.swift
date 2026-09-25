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

    private func isOn(_ action: HelmToolbarAction) -> Bool? {
        guard case let .toggle(on, _) = action.kind else { return nil }
        return on
    }

    private func press(_ action: HelmToolbarAction) {
        guard case let .toggle(_, perform) = action.kind else {
            XCTFail("\(action.id) is not a toggle")
            return
        }
        perform()
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

    // MARK: - The view pair

    /// **The pair is a `Table`/`Plain text` toggle mapped onto two toggle
    /// actions in the capsule** (`HostsSettingsPage.toolbarContent`'s own
    /// doc names the alternative not taken: one glyph that flips between the
    /// two modes).
    func testTheViewPairShowsOnlyOnSSHAndPressingPlainTextTurnsItOnAndDrawsTheEditor() async throws {
        let hosted = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined)
        let channel = HelmWindowToolbarChannel()
        let mounted = await mountPage(hosted, channel: channel)

        var declared = try XCTUnwrap(declaredContent(channel))
        var table = try XCTUnwrap(declared.actions.first { $0.id == "tableView" })
        var text = try XCTUnwrap(declared.actions.first { $0.id == "textView" })
        XCTAssertFalse(table.isVisible, "the view pair must not show on the Keys tab")
        XCTAssertFalse(text.isVisible, "the view pair must not show on the Keys tab")

        let selectedTab = try XCTUnwrap(declared.selectedTab)
        selectedTab.wrappedValue = "ssh"
        mounted.settle(30)

        declared = try XCTUnwrap(declaredContent(channel))
        table = try XCTUnwrap(declared.actions.first { $0.id == "tableView" })
        text = try XCTUnwrap(declared.actions.first { $0.id == "textView" })
        XCTAssertTrue(table.isVisible, "the view pair must show on the SSH tab")
        XCTAssertTrue(text.isVisible, "the view pair must show on the SSH tab")
        XCTAssertEqual(isOn(table), true, "Table starts on")
        XCTAssertEqual(isOn(text), false, "Plain text starts off")
        XCTAssertNil(mounted.host.everyView(ofType: NSTextView.self).first { $0.string.contains("Host a") },
                    "the config's text editor must not be on screen while Table is showing")

        press(text)
        mounted.settle(30)

        declared = try XCTUnwrap(declaredContent(channel))
        table = try XCTUnwrap(declared.actions.first { $0.id == "tableView" })
        text = try XCTUnwrap(declared.actions.first { $0.id == "textView" })
        XCTAssertEqual(isOn(table), false, "Table turns off once Plain text is pressed")
        XCTAssertEqual(isOn(text), true, "Plain text turns on when pressed")
        XCTAssertNotNil(mounted.host.everyView(ofType: NSTextView.self).first { $0.string.contains("Host a") },
                        "the SSH config's text editor must be on screen once Plain text is on")
    }

    func testTheViewPairIsDimmedWhenTheSSHConfigCannotBeRead() async throws {
        let hosted = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined,
                                      sshConfig: UnreadableSSHConfig())
        let channel = HelmWindowToolbarChannel()
        let mounted = await mountPage(hosted, channel: channel)

        let selectedTab = try XCTUnwrap(declaredContent(channel)?.selectedTab)
        selectedTab.wrappedValue = "ssh"
        mounted.settle(30)

        let declared = try XCTUnwrap(declaredContent(channel))
        let table = try XCTUnwrap(declared.actions.first { $0.id == "tableView" })
        let text = try XCTUnwrap(declared.actions.first { $0.id == "textView" })
        XCTAssertFalse(table.isEnabled, "the view pair must be dimmed once the SSH config cannot be read")
        XCTAssertFalse(text.isEnabled, "the view pair must be dimmed once the SSH config cannot be read")
    }
}
