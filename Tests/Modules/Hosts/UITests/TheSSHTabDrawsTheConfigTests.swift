import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import HelmTestSupport
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// Tab 2 as the page draws it, and as the model answers for it.
///
/// The assertions are on the **model** rather than on pixels, for the reason
/// the VPN strip's tests record: there is no way to read a string back out of an
/// offscreen SwiftUI render on this SDK, so a test written against the drawing
/// would pass every «does not contain» for free. What the render is used for
/// here is what a render can answer — that mounting the page with a config in
/// it does not trap, and that the table and the text view are the same document.
@MainActor
final class TheSSHTabDrawsTheConfigTests: XCTestCase {

    private let config = """
    Host build
        HostName build.example
        User rstrlnkv
        Port 2222

    Match host build
        HostName build.vpn.example

    """

    private func model(_ state: HostsState) -> HostsViewModel {
        let transport = LocalTransport()
        let model = HostsViewModel(vm: ModuleViewModel(transport: transport))
        model.adopt(state)
        return model
    }

    /// The table's rows are the blocks, and a `Match` is not one of them — the
    /// parser's rule reaching the screen, where it decides what a person is
    /// offered.
    func testTheTableDrawsOneBlockPerHostAndNoneForAMatch() {
        let hvm = model(HostsState(sshText: config))
        XCTAssertEqual(hvm.sshDocument.hosts.map(\.patterns), ["build"])
        XCTAssertEqual(hvm.sshDocument.fields(ofHost: 0).map(\.name),
                       [.hostName, .user, .port])
    }

    /// A row edit and a keystroke in the text view are one edit to one file:
    /// the text is canonical and the table is derived from it on every read.
    func testARowEditIsTheSameEditAsTypingInTheTextView() {
        let hvm = model(HostsState(sshText: config))
        XCTAssertTrue(hvm.setSSHField("22", of: .port, ofHost: 0))
        XCTAssertTrue(hvm.sshText.contains("Port 22\n"), hvm.sshText)
        XCTAssertTrue(hvm.sshHasUnsavedChanges)
        hvm.revertSSH()
        XCTAssertEqual(hvm.sshText, config)
        XCTAssertFalse(hvm.sshHasUnsavedChanges)
    }

    /// The refusal reaches the model as «nothing happened», and the document is
    /// untouched — the field keeps what it had, which is what a control that
    /// refuses a keystroke looks like.
    func testAHostileValueIsRefusedAndTheDocumentIsUntouched() {
        let hvm = model(HostsState(sshText: config))
        XCTAssertFalse(hvm.setSSHField("x\nProxyCommand nc evil 22", of: .hostName, ofHost: 0))
        XCTAssertEqual(hvm.sshText, config)
    }

    /// A snapshot landing while somebody is mid-edit updates what «revert»
    /// means and does not take their typing away — the rule tab 1 already
    /// lives by, and this file is edited in other editors just as often.
    func testASnapshotDoesNotTakeUnsavedTypingAway() {
        let hvm = model(HostsState(sshText: config))
        hvm.setSSHText("Host mine\n")
        hvm.adopt(HostsState(sshText: "Host theirs\n"))
        XCTAssertEqual(hvm.sshText, "Host mine\n", "the snapshot overwrote unsaved typing")
        XCTAssertTrue(hvm.sshHasUnsavedChanges)
        hvm.revertSSH()
        XCTAssertEqual(hvm.sshText, "Host theirs\n", "revert did not mean what disk says")
    }

    /// «Not readable» is not «empty», and the page draws a different thing for
    /// each — a table over a config that could not be read would invite a save
    /// that overwrites whatever is really there.
    func testAnUnreadableConfigIsNotAnEmptyOne() {
        let hvm = model(HostsState(sshText: "", sshReadable: false))
        XCTAssertFalse(hvm.sshReadable)
        XCTAssertTrue(hvm.sshDocument.hosts.isEmpty)
    }

    /// The page mounts with a config in it. A render, because a page that traps
    /// on a document is a defect no model-level test can see.
    func testThePageMountsWithAConfigWithoutTrapping() {
        let hvm = model(HostsState(hostsText: "127.0.0.1\tlocalhost\n", sshText: config))
        let render = MountedRender(SSHConfigTable(hvm: hvm), width: 720, height: 400,
                                   appearance: .darkAqua)
        render.settle(10)
        XCTAssertGreaterThan(render.host.fittingSize.height, 0)
        render.drop()
    }
}
