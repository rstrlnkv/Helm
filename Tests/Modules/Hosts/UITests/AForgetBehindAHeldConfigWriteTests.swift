import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **A Forget pressed while an earlier config write is still held.**
///
/// The engine runs the config's writes and Forget's on one serial queue, so a
/// Forget waits for whatever config write is ahead of it. Apply has a deadline
/// that lets the page go (`sshWriteDeadline`); Forget has none. A config write
/// held by the volume `~/.ssh/config` lives on — often a dotfiles checkout
/// reached through a link, which `SSHFileScope` lets through on purpose, while
/// `known_hosts` sits on the local disk — therefore holds every Forget behind it
/// for as long as that volume is away: `forgetting` stays set, every Forget
/// button on the tab is disabled and the pressed row stays dimmed, and nothing on
/// the page says why.
///
/// The bound here is generous: the Apply's own deadline plus five seconds. What
/// it asks is only that a Forget ends inside the sitting while a config write it
/// has nothing to do with is held.
@MainActor
final class AForgetBehindAHeldConfigWriteTests: XCTestCase {

    /// A config port whose writes wait until the test lets them go, and give up
    /// on their own after `ceiling` seconds so a failing test leaves no thread.
    private final class Held: SSHConfigPort, @unchecked Sendable {
        let url: URL
        private let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private let ceiling: TimeInterval
        private var entered = 0
        private var finished = 0
        init(_ url: URL, ceiling: TimeInterval) { self.url = url; self.ceiling = ceiling }
        var inside: Int { lock.withLock { entered } }
        var done: Int { lock.withLock { finished } }
        func release() { gate.signal() }
        func read() -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func write(_ text: String) -> Bool {
            lock.withLock { entered += 1 }
            _ = gate.wait(timeout: .now() + ceiling)
            let ok = (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
            lock.withLock { finished += 1 }
            return ok
        }
    }

    /// `known_hosts` on a disk that answers at once.
    private final class StoredKnownHosts: KnownHostsPort, @unchecked Sendable {
        let url: URL
        private let lock = NSLock()
        private var stored: String
        init(url: URL, text: String) { self.url = url; self.stored = text }
        var text: String { lock.withLock { stored } }
        func read() -> String? { lock.withLock { stored } }
        func write(_ text: String) -> Bool { lock.withLock { stored = text }; return true }
    }

    private var keep: [AnyObject] = []
    override func tearDown() async throws {
        await MainActor.run {
            keep.compactMap { $0 as? HostsViewModel }.forEach { $0.stop() }
            keep = []
        }
    }

    private func wait(_ seconds: TimeInterval, until condition: () -> Bool) async throws {
        let start = Date()
        while !condition(), Date().timeIntervalSince(start) < seconds {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testAForgetEndsWhileAConfigWriteIsHeld() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_KNOWN_GAPS"] == "1", "Known gap H4: Forget has no deadline and waits behind a held config write.")
        let home = scratchDirectory("hosts-forget-behind-held")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let configURL = ssh.appendingPathComponent("config")
        try "Host a\n    HostName a.example\n".write(to: configURL, atomically: true, encoding: .utf8)
        let knownURL = ssh.appendingPathComponent("known_hosts")
        let trusts = "github.com ssh-ed25519 AAAAB3Nza me@mac\nold.example ssh-rsa AAAAB3Nza me@mac\n"
        try trusts.write(to: knownURL, atomically: true, encoding: .utf8)

        let ceiling: TimeInterval = 20
        let config = Held(configURL, ceiling: ceiling)
        let known = StoredKnownHosts(url: knownURL, text: trusts)
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(), sshConfig: config,
                                 knownHosts: known, keys: WireKeys(), agent: WireAgent(),
                                 generator: WireKeyGenerator(), home: home,
                                 now: { Date(timeIntervalSince1970: 0) }, transport: LocalTransport())
        keep.append(engine)
        let hvm = HostsViewModel(vm: ModuleViewModel(transport: engine.transport))
        keep.append(hvm)
        await hvm.firstLoad?.value
        try await wait(3) { !hvm.knownHostsText.isEmpty }
        hvm.sshWriteDeadline = 0.3

        hvm.setSSHText(hvm.sshText + "# sent\n")
        await hvm.applySSH()
        XCTAssertEqual(config.inside, 1, "precondition: the config write never reached the port")
        XCTAssertEqual(config.done, 0, "precondition: the config write was not held")
        XCTAssertEqual(hvm.sshOutcome, .failed, "precondition: the Apply ran out its deadline")

        guard let entry = hvm.otherTrusted.first(where: { $0.hosts == ["github.com"] }) else {
            return XCTFail("the trusts on the page are \(hvm.otherTrusted.map(\.hosts))")
        }
        // Finished is read off the press's own task, not off `forgetting`: the
        // task has not started when the wait first looks, and `forgetting` is
        // nil then too.
        final class Ended { var at: Date? }
        let ended = Ended()
        let start = Date()
        let forget = Task { await hvm.forget(entry); ended.at = Date() }
        try await wait(hvm.sshWriteDeadline + 5) { ended.at != nil }
        let took = (ended.at ?? Date()).timeIntervalSince(start)
        let stuck = ended.at == nil
        let dimmedWhileStuck = hvm.forgetting
        let heldStill = config.done == 0
        config.release()
        await forget.value

        XCTAssertTrue(heldStill, "precondition: the config write was still held while Forget ran")
        XCTAssertFalse(known.text.contains("github.com"),
                       "precondition: the Forget did its work at all — \(known.text)")
        XCTAssertFalse(stuck, """
            Forget on known_hosts was still running \(String(format: "%.1f", took)) s after it \
            was pressed, behind a config write it has nothing to do with: every Forget button on \
            the tab stays disabled and the row dimmed for as long as that write is held, and \
            there is no deadline to end it (forgetting = \(String(describing: dimmedWhileStuck)))
            """)
    }
}
