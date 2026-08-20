import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **Two subjects share one event name, and one of them shares its words.**
///
/// `HostsOperation` is the engine's «something is running, and here is what the
/// last one came to». It is emitted by `apply` — the privileged write of
/// `/etc/hosts` — and by `generate`, which makes a key. The view model reads
/// that one event into `applying` and `lastOutcome`, and `lastOutcome` is a
/// `HostsOutcome`, built by `init(rawValue:)` from whatever string arrived.
///
/// `GenerateOutcome.failed.rawValue` is `"failed"`. So is
/// `HostsOutcome.failed.rawValue`. A key that could not be made therefore
/// arrives at the page as **the hosts file could not be written** — a sentence
/// about a file nobody touched, sitting in the bar above an unsaved document,
/// beside a Revert. And `applying`, which disables Apply, is on for as long as
/// a key takes to make: seconds, for RSA 4096.
///
/// This is `LocalTransport`'s own lesson one layer up: «one slot is right for
/// one event name and wrong for two», which is what left Homebrew's page idle
/// with an operation running behind it. Here the two are not even the same
/// subject.
///
/// The `/etc/hosts` editor is off the screen today and every part of it is
/// still here and still checked — the page's own comment says putting the tab
/// back is one line. The model is what is asked below, because that is what
/// would be wrong on the day it comes back.
///
/// **Neither reading is an absence.** «The generation did not set the flag» is
/// green when nothing was delivered at all, so each is preceded by the same
/// reading taken over a real `apply` on the same model and the same wire: the
/// control has to show the value moving before the subject is asked to leave it
/// alone. Measured — a first draft of the second test read `applying` straight
/// after the tool was reached and passed once in three runs, because
/// `waitUntil` yields only while its condition is false and the model's event
/// task never got a turn.
@MainActor
final class AGenerationIsNotAnApplyTests: XCTestCase {

    private lazy var home: URL = scratchDirectory("hosts-generation")
    /// **Held.** The transport's handler captures the engine weakly, so an
    /// engine nobody refers to answers every later command with empty `Data` —
    /// the trap `HostsViewModel.shared(vm:)` records next door.
    private var engines: [HostsEngine] = []

    /// A generator that fails the way the real one does when `ssh-keygen`
    /// cannot write — and that can sit at the prompt, which is where an RSA
    /// 4096 key spends its seconds.
    private final class WireGenerator: KeyGeneratorPort, @unchecked Sendable {
        private let status: Int32
        private let holds: Bool
        private let released = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var asked = false

        init(status: Int32 = 1, sitsAtThePrompt: Bool = false) {
            self.status = status
            self.holds = sitsAtThePrompt
        }

        /// Read by an `await waitUntil`, never by a semaphore the test blocks
        /// on: the generation runs behind a `@MainActor` model, and a main
        /// thread parked in `wait()` is a main thread the call cannot get past.
        var isAtThePrompt: Bool { lock.withLock { asked } }
        func finish() { for _ in 0..<8 { released.signal() } }

        func generate(_ arguments: [String], answering secret: inout Data) -> Int32 {
            secret = Data()
            lock.withLock { asked = true }
            if holds { _ = released.wait(timeout: .now() + 10) }
            return status
        }
    }

    /// The password dialog, still on screen. The control for «is `applying` a
    /// live wire» needs a write that has not finished, and `FixedPrivileged`
    /// answers on the spot.
    private final class SittingPrivileged: PrivilegedPort, @unchecked Sendable {
        private let released = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var up = false

        var dialogIsUp: Bool { lock.withLock { up } }
        func answerTheDialog() { for _ in 0..<8 { released.signal() } }

        func run(_ command: String) -> PrivilegedOutcome {
            lock.withLock { up = true }
            _ = released.wait(timeout: .now() + 10)
            return .declined
        }
    }

    private func model(_ generator: KeyGeneratorPort,
                       privileged: PrivilegedPort = FixedPrivileged(.declined))
        async -> HostsViewModel {
        let transport = LocalTransport()
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: privileged,
                                 backups: MemoryBackups(), sshConfig: WireSSHConfig(),
                                 knownHosts: WireKnownHosts(), keys: WireKeys(),
                                 agent: WireAgent(), generator: generator,
                                 home: home, transport: transport)
        engines.append(engine)
        let model = HostsViewModel(vm: ModuleViewModel(transport: engine.transport))
        addTeardownBlock { await MainActor.run { model.stop() } }
        // Held and awaited before anything is counted: the model fires its own
        // load from `init`, and a second reader racing the first on one wire is
        // 8 failures in 200 constructions.
        await model.firstLoad?.value
        await waitUntil("the first snapshot arrived") { !model.keys.isEmpty }
        return model
    }

    /// The event task and the caller's resumption are both on this actor and
    /// their order is nobody's promise, so a reading of what the model was told
    /// is taken after the queue has been given a great many turns.
    private func drain() async {
        for _ in 0..<500 { await Task.yield() }
    }

    /// A key that could not be made says so about the key, and says nothing
    /// about `/etc/hosts`.
    func testAFailedGenerationDoesNotSpeakForTheHostsFile() async {
        let hvm = await model(WireGenerator(status: 1))

        // The control: a real apply, on this model and this wire. It sets the
        // outcome the page draws, so what follows is «did the generation move a
        // live value» rather than «did an event arrive at all».
        await hvm.apply()
        await drain()
        XCTAssertEqual(hvm.lastOutcome, .declined,
                       "the control never landed: the page is not being told about applies, so "
                       + "the reading below is about nothing")

        await hvm.generate(type: .ed25519, name: "fresh_key", comment: "me@mac", passphrase: "")
        await drain()

        XCTAssertEqual(hvm.generated, .failed, "precondition: the generation failed at all")
        XCTAssertEqual(hvm.lastOutcome, .declined, """
            the generation's outcome arrived as the hosts file's — the page's last word about \
            /etc/hosts is \(String(describing: hvm.lastOutcome)) now. `GenerateOutcome.failed` \
            and `HostsOutcome.failed` spell the same string, so the bar says the hosts file \
            could not be written about a file this act never opened. Two subjects, one event \
            name, one string namespace.
            """)
    }

    /// And while a key is being made the page must not report that a privileged
    /// write is in flight. `applying` is what disables Apply and what the
    /// unsaved bar draws itself from.
    func testAKeyBeingMadeIsNotAWriteInFlight() async {
        let generator = WireGenerator(status: 0, sitsAtThePrompt: true)
        let dialog = SittingPrivileged()
        let hvm = await model(generator, privileged: dialog)

        // The control, again on the same model: a write that has not finished
        // does set the flag, and this reading — taken the same way, after the
        // same drain — sees it.
        let applying = Task { await hvm.apply() }
        await waitUntil("the dialog is up") { dialog.dialogIsUp }
        await drain()
        XCTAssertTrue(hvm.applying,
                      "the control never landed: `applying` does not follow a write in flight, "
                      + "so the reading below cannot say anything about a generation")
        dialog.answerTheDialog()
        await applying.value
        await drain()
        XCTAssertFalse(hvm.applying, "precondition: the flag came back down")

        let making = Task { await hvm.generate(type: .rsa, name: "fresh_key",
                                               comment: "me@mac", passphrase: "") }
        await waitUntil("the generation reached the tool") { generator.isAtThePrompt }
        await drain()
        let applyingWhileMakingAKey = hvm.applying
        generator.finish()
        await making.value

        XCTAssertFalse(applyingWhileMakingAKey, """
            making a key set the flag that means «a privileged write of /etc/hosts is running». \
            Apply is disabled from it and the unsaved bar draws itself from it, so a person with \
            edits waiting cannot save them while a key is being generated — and nothing on the \
            page says why.
            """)
    }
}
