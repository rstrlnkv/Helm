import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **A write that does not come back ends at a deadline, says so, and a late
/// answer is read against what was sent.**
///
/// The model outlives the page, so a flag with no end kept Revert and Apply grey
/// across closing and reopening the window, with nothing on the strip. The port
/// here holds the write on a semaphore the test releases itself, so the test
/// stands inside the write as long as it likes.
@MainActor
final class AnApplyThatNeverAnswersEndsTests: XCTestCase {

    private final class Hung: SSHConfigPort, @unchecked Sendable {
        let url: URL
        let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var entered = 0
        init(_ url: URL) { self.url = url }
        var inside: Int { lock.lock(); defer { lock.unlock() }; return entered }
        func read() -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func write(_ text: String) -> Bool {
            lock.lock(); entered += 1; lock.unlock()
            _ = gate.wait(timeout: .now() + 30)
            return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
        }
    }

    private var keep: [AnyObject] = []
    override func tearDown() async throws { await MainActor.run { keep.compactMap { $0 as? HostsViewModel }.forEach { $0.stop() }; keep = [] } }

    private func hung() async throws -> (hvm: HostsViewModel, config: Hung) {
        let home = scratchDirectory("hosts-hung")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let url = ssh.appendingPathComponent("config")
        try "Host a\n    HostName a.example\n".write(to: url, atomically: true, encoding: .utf8)
        let config = Hung(url)
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"), privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(), sshConfig: config, knownHosts: WireKnownHosts(),
                                 keys: WireKeys(), agent: WireAgent(), generator: WireKeyGenerator(), home: home,
                                 now: { Date(timeIntervalSince1970: 0) }, transport: LocalTransport())
        keep.append(engine)
        let hvm = HostsViewModel.shared(vm: ModuleViewModel(transport: engine.transport))
        keep.append(hvm)
        await hvm.firstLoad?.value
        hvm.sshWriteDeadline = 0.3
        hvm.setSSHText(hvm.sshText + "# typed\n")
        return (hvm, config)
    }

    private func enter(_ config: Hung) async throws {
        let start = Date()
        while config.inside == 0, Date().timeIntervalSince(start) < 3 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(config.inside, 1, "precondition — the engine never reached the write")
    }

    func testAWriteThatNeverAnswersReleasesTheStripAndSaysItWasNotSaved() async throws {
        let (hvm, config) = try await hung()
        let apply = Task { await hvm.applySSH() }
        try await enter(config)
        await apply.value
        XCTAssertFalse(hvm.sshApplying, "the deadline passed and Revert and Apply are still grey")
        XCTAssertEqual(hvm.sshOutcome, .failed, "nothing is said on the strip about a write that did not answer")
        XCTAssertTrue(hvm.sshHasUnsavedChanges, "the edit was taken off the screen or called saved")
        config.gate.signal()
    }

    func testALateAnswerAboutTheSameTextIsSaidAsWhatItIs() async throws {
        let (hvm, config) = try await hung()
        let apply = Task { await hvm.applySSH() }
        try await enter(config)
        await apply.value
        config.gate.signal()
        let start = Date()
        while hvm.sshOutcome != .applied, Date().timeIntervalSince(start) < 3 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(hvm.sshOutcome, .applied, "the write finished and the strip still says it failed")
        XCTAssertFalse(hvm.sshHasUnsavedChanges)
    }

    func testALateAnswerDoesNotOverwriteTextThatMovedSinceItWasSent() async throws {
        let (hvm, config) = try await hung()
        let apply = Task { await hvm.applySSH() }
        try await enter(config)
        await apply.value
        hvm.setSSHText(hvm.sshText + "# and more\n")
        config.gate.signal()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNotEqual(hvm.sshOutcome, .applied, "a late answer about older text was said over the newer text")
        XCTAssertTrue(hvm.sshText.contains("# and more"), "the newer edit was taken off the screen")
        XCTAssertTrue(hvm.sshHasUnsavedChanges)
    }
}
