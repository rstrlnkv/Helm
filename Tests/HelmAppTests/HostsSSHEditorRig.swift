import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **Hosts' page on its SSH tab in the text editor, in a window that holds Helm's own page bar
/// (`LivePageToolbarFixture`), and a person's keystrokes into that editor.**
///
/// No family builds it: the two keystroke families read the toolbar through `LivePageInTheToolbarFixture`.
/// `keystroke()` is what the page does for one typed character, `HostsViewModel.setSSHText(_:)`, which
/// publishes and so makes the page declare its toolbar again. `redeclares` counts the declarations that
/// reached the bar: the bar installs its handler on the channel's single `onChange` slot, and the count
/// wraps that handler, so a number short of the keystrokes typed means the bar never heard them.
///
/// The bar reads settings when it is built; a test calls `PinnedBarSettings.pin(in:)` first.
@MainActor
final class HostsSSHEditorRig {

    private final class Mute: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    final class Count { var value = 0 }
    struct RigFailed: Error {}

    let fixture: LivePageToolbarFixture
    let redeclares = Count()
    /// What Hosts declared on its SSH tab once the editor was up.
    let declared: HelmPageToolbarContent
    private let hostsModel: HostsViewModel
    private var typed = "Host example"
    private var index = 0

    /// Mounts Hosts, goes to the SSH tab and the text view, and checks that the editor is there to type into.
    static func make() throws -> HostsSSHEditorRig {
        let vm = ModuleViewModel(transport: Mute())
        let fixture = LivePageToolbarFixture(HostsSettingsPage(vm: vm),
                                             selection: .module(HostsDescriptor.id.rawValue),
                                             width: 1060, height: 700)
        do {
            fixture.settle(30)
            let id = HostsDescriptor.id.rawValue
            let onKeys = try XCTUnwrap(fixture.channel.content(for: id), "Hosts declared nothing onto the channel")
            try XCTUnwrap(onKeys.selectedTab, "Hosts declared no tabs").wrappedValue = "ssh"
            fixture.settle(30)
            let onSSH = try XCTUnwrap(fixture.channel.content(for: id))
            XCTAssertFalse(onSSH.tabs.isEmpty, "precondition: Hosts declared no centre tabs")
            let viewMode = try XCTUnwrap(onSSH.actions.first { $0.id == "viewMode" }, "Hosts declared no viewMode")
            guard case .segmented(_, let mode) = viewMode.kind else {
                XCTFail("precondition: Hosts' viewMode is not a .segmented action")
                throw RigFailed()
            }
            mode.wrappedValue = "text"
            fixture.settle(30)
            XCTAssertFalse(fixture.mount.host.everyView(ofType: NSTextView.self).isEmpty,
                           "precondition: the SSH tab shows no text editor to type into")
            let declared = try XCTUnwrap(fixture.channel.content(for: id))
            return HostsSSHEditorRig(fixture: fixture, declared: declared, hostsModel: HostsViewModel.shared(vm: vm))
        } catch {
            fixture.drop()
            throw error
        }
    }

    private init(fixture: LivePageToolbarFixture, declared: HelmPageToolbarContent, hostsModel: HostsViewModel) {
        self.fixture = fixture
        self.declared = declared
        self.hostsModel = hostsModel
        let count = redeclares
        let forward = fixture.channel.onChange
        fixture.channel.onChange = { count.value += 1; forward?() }
    }

    /// One more character in the SSH config, and the page laid out.
    func keystroke() {
        typed += "\(index % 10)"
        index += 1
        hostsModel.setSSHText(typed + "\n")
        fixture.mount.host.layoutSubtreeIfNeeded()
    }

    /// The editor holds what has been typed so far: the keystrokes reached the page, not only its model.
    var editorHoldsWhatWasTyped: Bool {
        fixture.mount.host.everyView(ofType: NSTextView.self).contains { $0.string.contains(typed) }
    }

    func drop() { fixture.drop() }
}
