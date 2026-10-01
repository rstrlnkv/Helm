import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **Revert forgets the config's refusal and nothing else.**
///
/// Revert throws away an edit to `~/.ssh/config`, and so forgets the sentence
/// about that edit's failed Apply (`ARevertedSSHEditForgetsItsFailureTests`).
/// A Forget that `known_hosts` refused is about a different file and a
/// different act; the same strip carries it, and a Revert of the config must
/// leave it standing — both in the model and on the strip over the text box.
@MainActor
final class ARevertLeavesTheKnownHostsRefusalTests: XCTestCase {

    private var benches: [SSHStripBench] = []

    override func tearDown() async throws {
        await MainActor.run { benches.forEach { $0.drop() }; benches = [] }
    }

    func testARefusedForgetOutlivesARevertOfTheConfig() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let bench = try await SSHStripBench(appearance, directory: scratchDirectory("hosts-strip-known"),
                                                knownWrites: false, mode: "table")
            benches.append(bench)
            let entry = try XCTUnwrap(KnownHostsFile.parse(SSHStripBench.trusted).entries.first)
            await bench.hvm.forget(entry)
            let refusal = try XCTUnwrap(bench.hvm.knownHostsOutcome, "\(what): precondition — the Forget came back with nothing")
            XCTAssertNotEqual(refusal, .applied, "\(what): precondition — the refusing file took the Forget")
            try bench.select(mode: "text")
            bench.mounted.settle(40)
            let withRefusal = try XCTUnwrap(bench.boxTop)
            XCTAssertGreaterThan(withRefusal, HostsSettingsPage.textBoxMargin + 10,
                                 "\(what): precondition — the strip did not say the refusal")

            let tv = try XCTUnwrap(bench.textView)
            bench.mounted.window?.makeFirstResponder(tv)
            tv.insertText("# typed\n", replacementRange: NSRange(location: 0, length: 0))
            bench.mounted.settle(40)
            XCTAssertTrue(bench.hvm.sshHasUnsavedChanges, "\(what): precondition — the keystroke made no edit")
            bench.hvm.revertSSH()
            bench.mounted.settle(40)
            XCTAssertFalse(bench.hvm.sshHasUnsavedChanges, "\(what): precondition — Revert left the edit")

            XCTAssertEqual(bench.hvm.knownHostsOutcome, refusal,
                           "\(what): Revert of the config took the known_hosts refusal with it")
            let after = try XCTUnwrap(bench.boxTop)
            XCTAssertEqual(after, withRefusal, accuracy: 0.5,
                           "\(what): the strip went from \(withRefusal) to \(after) — the refusal is no longer said")
            // Only read when there is a strip to read: a band ending above its
            // own start is a trap, not a reading.
            let stripRows = Int(after - HostsSettingsPage.textBoxMargin) - 1
            if stripRows > 1 {
                let ink = try XCTUnwrap(bench.mounted.ink(0...stripRows))
                XCTAssertGreaterThan(ink, 0, "\(what): the strip stands open over nothing")
            }
            bench.drop()
        }
    }
}
