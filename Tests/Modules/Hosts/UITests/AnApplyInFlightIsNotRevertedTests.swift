import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **While the config is being written, Revert does nothing, and the answer is
/// read against what was sent.**
///
/// Hosts has `applying` and disables both buttons on it; SSH had no such flag,
/// so Revert pressed with the engine inside the write threw the edit away on
/// screen and then the answer arrived about text that was gone: a refusal read
/// «could not be saved» over an unedited file, and a success brought the
/// reverted edit back as saved.
///
/// The port here holds the write on a semaphore, so the test stands inside the
/// write for as long as it likes — a port answering at once would release the
/// gate before the call it gates returned.
@MainActor
final class AnApplyInFlightIsNotRevertedTests: XCTestCase {

    private final class GatedConfig: SSHConfigPort, @unchecked Sendable {
        let url: URL
        let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var inside = false
        let writes: Bool
        init(_ url: URL, writes: Bool) { self.url = url; self.writes = writes }
        var isInside: Bool { lock.lock(); defer { lock.unlock() }; return inside }
        func read() -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func write(_ text: String) -> Bool {
            lock.lock(); inside = true; lock.unlock()
            _ = gate.wait(timeout: .now() + 5)
            guard writes else { return false }
            return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
        }
    }

    private var engines: [HostsEngine] = []

    override func tearDown() async throws { await MainActor.run { engines = [] } }

    /// An edit typed and Apply pressed, the engine standing inside the write.
    private func inFlight(writes: Bool) async throws -> (hvm: HostsViewModel, config: GatedConfig, apply: Task<Void, Never>) {
        let home = scratchDirectory("hosts-inflight")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let url = ssh.appendingPathComponent("config")
        try "Host a\n    HostName a.example\n".write(to: url, atomically: true, encoding: .utf8)
        let config = GatedConfig(url, writes: writes)
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(),
                                 sshConfig: config, knownHosts: WireKnownHosts(),
                                 keys: WireKeys(), agent: WireAgent(),
                                 generator: WireKeyGenerator(),
                                 home: home,
                                 now: { Date(timeIntervalSince1970: 0) },
                                 transport: LocalTransport())
        engines.append(engine)
        let hvm = HostsViewModel.shared(vm: ModuleViewModel(transport: engine.transport))
        await hvm.firstLoad?.value
        hvm.setSSHText(hvm.sshText + "# typed\n")
        let apply = Task { await hvm.applySSH() }
        let deadline = Date().addingTimeInterval(3)
        while !config.isInside, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(config.isInside, "precondition — the engine never reached the write")
        return (hvm, config, apply)
    }

    func testRevertDuringARefusedWriteLeavesTheEditAndTheRefusalSaysSo() async throws {
        let (hvm, config, apply) = try await inFlight(writes: false)
        XCTAssertTrue(hvm.sshApplying, "the model does not know a write is in flight")
        hvm.revertSSH()
        XCTAssertTrue(hvm.sshHasUnsavedChanges,
                      "Revert took the edit off the screen while the engine was still writing it")
        config.gate.signal()
        await apply.value
        XCTAssertFalse(hvm.sshApplying, "the flag outlived the write")
        XCTAssertEqual(hvm.sshOutcome, .failed, "the refusal was not said")
        XCTAssertTrue(hvm.sshHasUnsavedChanges, "the refused edit is gone from the screen")
    }

    func testRevertDuringASuccessfulWriteDoesNotBringTheEditBackAsSaved() async throws {
        let (hvm, config, apply) = try await inFlight(writes: true)
        hvm.revertSSH()
        XCTAssertTrue(hvm.sshHasUnsavedChanges,
                      "Revert took the edit off the screen while the engine was still writing it")
        config.gate.signal()
        await apply.value
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(hvm.sshText.contains("# typed"), "what was written is not what is on screen")
        XCTAssertFalse(hvm.sshHasUnsavedChanges, "the written text still reads as unsaved")
        XCTAssertNotEqual(hvm.sshOutcome, .failed)
    }

    /// Typing is not blocked during a write, so the answer can be about text
    /// that is no longer the text: a refusal of the old one is not said over
    /// the new one.
    func testARefusalIsNotSaidAboutTextThatMovedSinceItWasSent() async throws {
        let (hvm, config, apply) = try await inFlight(writes: false)
        hvm.setSSHText(hvm.sshText + "# and more\n")
        config.gate.signal()
        await apply.value
        XCTAssertNil(hvm.sshOutcome,
                     "the strip says \(String(describing: hvm.sshOutcome)) about text the engine was never sent")
        XCTAssertTrue(hvm.sshHasUnsavedChanges)
    }
}
