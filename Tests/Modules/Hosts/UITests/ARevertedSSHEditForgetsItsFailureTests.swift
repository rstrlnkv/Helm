import HelmContract
import HelmUI
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **A refusal is about an edit; once the edit is gone, so is the refusal.**
/// A failed Apply leaves `sshOutcome` on the model, and the strip says «could
/// not be saved» until something clears it. Revert throws the edit away — the
/// sentence would then be about text that is no longer on screen.
@MainActor
final class ARevertedSSHEditForgetsItsFailureTests: XCTestCase {

    private final class RefusingConfig: SSHConfigPort, @unchecked Sendable {
        let url: URL
        init(_ url: URL) { self.url = url }
        func read() -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func write(_ text: String) -> Bool { false }
    }

    private var engines: [HostsEngine] = []

    func testRevertClearsTheOutcomeOfTheEditItThrewAway() async throws {
        let home = scratchDirectory("hosts-revert-outcome")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let config = ssh.appendingPathComponent("config")
        try "Host a\n    HostName a.example\n".write(to: config, atomically: true, encoding: .utf8)
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(),
                                 sshConfig: RefusingConfig(config), knownHosts: WireKnownHosts(),
                                 keys: WireKeys(), agent: WireAgent(),
                                 generator: WireKeyGenerator(),
                                 home: home,
                                 now: { Date(timeIntervalSince1970: 0) },
                                 transport: LocalTransport())
        engines.append(engine)
        let vm = ModuleViewModel(transport: engine.transport)
        let hvm = HostsViewModel.shared(vm: vm)
        await hvm.firstLoad?.value

        hvm.setSSHText(hvm.sshText + "# typed\n")
        await hvm.applySSH()
        XCTAssertEqual(hvm.sshOutcome, .failed, "precondition: the refusing file took the write")
        XCTAssertTrue(hvm.sshHasUnsavedChanges, "precondition: no edit left to revert")

        hvm.revertSSH()
        XCTAssertFalse(hvm.sshHasUnsavedChanges, "precondition: Revert left the edit")
        XCTAssertNil(hvm.sshOutcome, "the strip still says the save failed, about an edit that is gone")
    }
}
