import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **What a second Apply meets after the first ran out its deadline.**
///
/// The deadline lets go of the page, not of the engine: the first write is still
/// inside the port. These stand in that state and press again, the way a person
/// reading «could not be saved» does.
///
/// Two defects stood here and are fixed; the cases keep them from coming back:
/// - The engine's handler is not serial, so a second write used to run beside the
///   held one and the two could finish in either order. Writes now go through the
///   engine's serial `sshWrites` queue.
/// - The write was a blocking call on the Swift-concurrency pool, so each Apply that
///   outlived its deadline kept a pool thread, and the deadline's own timer runs
///   on that pool too. The write now waits on a continuation off the pool.
@MainActor
final class AWriteAfterTheDeadlineTests: XCTestCase {

    /// A config port that holds writes until the test lets them go, the way a
    /// home folder on a network volume whose server went away holds them.
    ///
    /// `holdAll` false holds the first write only, so a second one can pass it;
    /// true holds every write. A held write gives up on its own after `ceiling`
    /// seconds and then writes, so a test that fails cannot leave threads behind.
    private final class Held: SSHConfigPort, @unchecked Sendable {
        let url: URL
        private let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private let holdAll: Bool
        private let ceiling: TimeInterval
        private var entered = 0
        private var finished = 0
        init(_ url: URL, holdAll: Bool, ceiling: TimeInterval) {
            self.url = url; self.holdAll = holdAll; self.ceiling = ceiling
        }
        var inside: Int { lock.withLock { entered } }
        var done: Int { lock.withLock { finished } }
        func release(_ count: Int = 1) { for _ in 0..<count { gate.signal() } }
        func read() -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func write(_ text: String) -> Bool {
            let mine = lock.withLock { entered += 1; return entered }
            if holdAll || mine == 1 { _ = gate.wait(timeout: .now() + ceiling) }
            let ok = (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
            lock.withLock { finished += 1 }
            return ok
        }
    }

    private var keep: [AnyObject] = []
    override func tearDown() async throws {
        await MainActor.run {
            keep.compactMap { $0 as? HostsViewModel }.forEach { $0.stop() }
            keep = []
        }
    }

    private func make(holdAll: Bool, ceiling: TimeInterval) async throws -> (HostsViewModel, Held) {
        let home = scratchDirectory("hosts-after-deadline")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let url = ssh.appendingPathComponent("config")
        try "Host a\n    HostName a.example\n".write(to: url, atomically: true, encoding: .utf8)
        let config = Held(url, holdAll: holdAll, ceiling: ceiling)
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(), sshConfig: config,
                                 knownHosts: WireKnownHosts(), keys: WireKeys(), agent: WireAgent(),
                                 generator: WireKeyGenerator(), home: home,
                                 now: { Date(timeIntervalSince1970: 0) }, transport: LocalTransport())
        keep.append(engine)
        let hvm = HostsViewModel.shared(vm: ModuleViewModel(transport: engine.transport))
        keep.append(hvm)
        await hvm.firstLoad?.value
        hvm.sshWriteDeadline = 0.3
        return (hvm, config)
    }

    /// Waits by the clock, up to `seconds`, and answers whether `condition` held.
    @discardableResult
    private func wait(_ seconds: TimeInterval, until condition: () -> Bool) async throws -> Bool {
        let start = Date()
        while !condition(), Date().timeIntervalSince(start) < seconds {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    /// The first Apply runs out its deadline; the person edits and applies again;
    /// the first write then finishes. The newer text was sent last and has to be
    /// what the file holds, and the strip cannot say «Saved» over anything else.
    func testAnOlderWriteFinishingLateDoesNotLandOverANewerOne() async throws {
        let (hvm, config) = try await make(holdAll: false, ceiling: 20)
        hvm.setSSHText(hvm.sshText + "# first\n")
        let first = Task { await hvm.applySSH() }
        try await wait(3) { config.inside == 1 }
        XCTAssertEqual(config.inside, 1, "precondition: the engine never reached the first write")
        await first.value
        XCTAssertEqual(hvm.sshOutcome, .failed, "precondition: the first Apply ran out its deadline")

        hvm.setSSHText(hvm.sshText + "# second\n")
        let newer = hvm.sshText
        let second = Task { await hvm.applySSH() }
        // An engine that runs the second write beside the first finishes it here;
        // one that queues it behind the first does not, and the test goes on.
        try await wait(2) { config.done >= 1 }
        config.release()
        await second.value
        try await wait(5) { config.inside == 2 && config.done == 2 }
        XCTAssertEqual(config.done, 2, "precondition: both writes finished")
        try await Task.sleep(nanoseconds: 500_000_000)   // the state the last write emits

        XCTAssertEqual(config.read(), newer, """
            the file holds the older Apply's text: the first write, held past its deadline, \
            finished after the second and replaced it
            """)
        if hvm.sshOutcome == .applied {
            XCTAssertEqual(hvm.sshText, newer, """
                the strip says Saved over text that is not the newer edit — the older write's \
                state replaced the screen, and the newer edit is gone from the screen and the file
                """)
        }
    }

    /// The deadline said «could not be saved»; the person typed one more
    /// character; then the write landed. The file now holds what was sent, so the
    /// refusal on the strip is about a save that happened. An answer in time
    /// about text that has moved clears the strip (`applySSH`); a late one has to
    /// leave it no less honest.
    func testAWriteLandingAfterMoreTypingDoesNotLeaveCouldNotBeSaved() async throws {
        let (hvm, config) = try await make(holdAll: false, ceiling: 20)
        hvm.setSSHText(hvm.sshText + "# sent\n")
        let sent = hvm.sshText
        let apply = Task { await hvm.applySSH() }
        try await wait(3) { config.inside == 1 }
        await apply.value
        XCTAssertEqual(hvm.sshOutcome, .failed, "precondition: the Apply ran out its deadline")
        hvm.setSSHText(sent + "x")
        config.release()
        try await wait(5) { hvm.sshOnDisk == sent }
        XCTAssertEqual(hvm.sshOnDisk, sent, "precondition: the late write landed and was read back")
        XCTAssertNotEqual(hvm.sshOutcome, .failed, """
            the strip still says the SSH config could not be saved, over a file that holds \
            exactly what was sent
            """)
        XCTAssertEqual(hvm.sshText, sent + "x", "the newer keystroke was taken off the screen")
    }

    /// The model is let go (the module switched off) while the write it sent is
    /// still held. Nothing the Apply left behind may keep it: the request's task
    /// outlives the deadline by design, and a model it held strongly would be
    /// alive, and answering, for as long as the volume stays away.
    func testAModelLetGoMidWriteIsFreedWhileTheWriteIsStillHeld() async throws {
        weak var gone: HostsViewModel?
        var held: Held?
        do {
            let (hvm, config) = try await make(holdAll: false, ceiling: 20)
            held = config
            gone = hvm
            hvm.setSSHText(hvm.sshText + "# sent\n")
            await hvm.applySSH()
            XCTAssertEqual(config.inside, 1, "precondition: the engine never reached the write")
            XCTAssertEqual(hvm.sshOutcome, .failed, "precondition: the Apply ran out its deadline")
            hvm.stop()
            keep.removeAll { $0 === hvm }
        }
        try await wait(2) { gone == nil }
        let config = try XCTUnwrap(held)
        XCTAssertEqual(config.done, 0, "precondition: the write was still held when the model went")
        XCTAssertNil(gone, "the model outlived its last owner — something the Apply left holds it")
        config.release()
        try await wait(5) { config.done == 1 }
    }

    /// Every Apply after a hung one hangs too (each used to keep a thread of the
    /// Swift-concurrency pool; it now waits off it). The deadline must still end each press on time —
    /// past the pool's width included, which is where its own timer has nowhere
    /// left to run.
    func testTheDeadlineStillEndsAnApplyOnceManyWritesAreHung() async throws {
        let presses = ProcessInfo.processInfo.activeProcessorCount + 2
        let ceiling: TimeInterval = 8
        let (hvm, config) = try await make(holdAll: true, ceiling: ceiling)
        var late: [String] = []
        for press in 1...presses {
            hvm.setSSHText(hvm.sshText + "# press \(press)\n")
            let start = Date()
            await hvm.applySSH()
            let took = Date().timeIntervalSince(start)
            if took > hvm.sshWriteDeadline + 1.5 {
                late.append("press \(press): \(String(format: "%.1f", took)) s")
            }
            XCTAssertFalse(hvm.sshApplying, "press \(press) left Apply grey")
        }
        XCTAssertGreaterThanOrEqual(config.inside, 1, "precondition: no write reached the port")
        XCTAssertTrue(late.isEmpty, """
            a \(hvm.sshWriteDeadline) s deadline ended these presses only when a held write gave \
            up (\(ceiling) s), on a pool \(ProcessInfo.processInfo.activeProcessorCount) wide: \
            \(late.joined(separator: ", "))
            """)
        config.release(presses)
        try await wait(ceiling + 5) { config.done == presses }
        XCTAssertEqual(config.done, presses, "a held write never finished")
    }
}
