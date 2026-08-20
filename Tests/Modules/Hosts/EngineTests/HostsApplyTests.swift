import XCTest
import HelmContract
import HelmTestSupport
@testable import Module_Hosts_Engine

/// Copy, ask root, read back, compare — and what each step refuses.
final class HostsApplyTests: XCTestCase {

    // MARK: - Applying

    func testAnAppliedFileReachesTheDisk() async throws {
        let hosts = Hosts()
        let outcome = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(hosts.file.read(), "10.0.0.1\tbox\n")
    }

    func testTheOldContentIsSavedBeforeTheWrite() async throws {
        let hosts = Hosts()
        _ = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        let saved = try XCTUnwrap(hosts.backups.list().first)
        XCTAssertEqual(hosts.backups.read(saved), "127.0.0.1\tlocalhost\n")
    }

    /// The one that needs the lying fake. Without it this test passes with the
    /// verification deleted.
    func testAPortThatReportsSuccessOverAnUnchangedFileIsNotBelieved() async throws {
        let hosts = Hosts(.lie)
        let outcome = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        XCTAssertEqual(outcome, .notVerified)
        XCTAssertEqual(hosts.file.read(), "127.0.0.1\tlocalhost\n", "the fake was not lying")
    }

    /// Unchanged and destroyed are different disasters, and one read-back has
    /// to catch both. `>` opens before the pipeline runs and a pipeline's
    /// status is its last command's, so root really can report 0 over a file it
    /// emptied — a `.done` believed here is somebody's hosts file gone.
    func testAPortThatReportsSuccessOverAnEmptiedFileIsNotBelievedEither() async throws {
        let hosts = Hosts(.truncateAndLie)
        let outcome = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        XCTAssertEqual(outcome, .notVerified)
        XCTAssertEqual(hosts.file.read(), "", "the fake did not truncate, so this proves nothing")
    }

    func testACancelledDialogIsReportedAsDeclined() async throws {
        let hosts = Hosts(.decline)
        let outcome = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        XCTAssertEqual(outcome, .declined)
    }

    func testAFailedCommandIsReportedAsFailed() async throws {
        let hosts = Hosts(.fail(3))
        let outcome = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        XCTAssertEqual(outcome, .failed)
    }

    /// No backup, no attempt. A write with nothing to go back to is the one
    /// this module must not perform.
    func testNothingIsWrittenWhenTheBackupCouldNotBeSaved() async throws {
        let hosts = Hosts()
        hosts.backups.refusesToSave = true
        let outcome = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        XCTAssertEqual(outcome, .noBackup)
        XCTAssertEqual(hosts.file.read(), "127.0.0.1\tlocalhost\n")
        XCTAssertTrue(hosts.privileged.commands.isEmpty, "root was asked anyway")
    }

    /// A file that cannot be read cannot be copied, so it is never written
    /// over — and no backup is asked for, because there is nothing to save.
    func testAFileThatCannotBeReadIsNeverWrittenOver() async throws {
        let hosts = Hosts()
        hosts.file.changeUnderTheApp(to: nil)
        let outcome = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(hosts.privileged.commands.isEmpty)
        XCTAssertTrue(hosts.backups.list().isEmpty)
    }

    // MARK: - The ceiling

    /// The ceiling is legible, and it is not the gate's refusal wearing the
    /// same face. Nothing is written and no backup is taken, because nothing
    /// was attempted.
    func testAFileTooLargeToCarryIsSaidSoRatherThanFailed() async throws {
        let hosts = Hosts()
        XCTAssertFalse(HostsWrite.fits(Self.tooBig),
                       "the fixture is not actually over the ceiling")
        let outcome = try await apply(hosts.engine, Self.tooBig)
        XCTAssertEqual(outcome, .tooLarge)
        XCTAssertEqual(hosts.file.read(), "127.0.0.1\tlocalhost\n")
        XCTAssertTrue(hosts.privileged.commands.isEmpty)
        XCTAssertTrue(hosts.backups.list().isEmpty,
                      "a write that was never attempted took a backup")
    }

    /// **A refusal must not cost somebody their history.** Ten copies are kept;
    /// one taken for a write that never happens prunes the oldest real one, so
    /// a person holding a 2 MB file and pressing Apply ten times would lose
    /// every copy they had — to an operation that wrote nothing.
    func testARefusedFileDoesNotPruneTheCopiesAlreadyThere() async throws {
        let hosts = Hosts()
        hosts.fillTheBackups(10)
        let before = hosts.backups.list()
        XCTAssertEqual(before.count, 10, "fewer than the limit, so a prune would take nothing")

        let outcome = try await apply(hosts.engine, Self.tooBig)
        XCTAssertEqual(outcome, .tooLarge)
        XCTAssertEqual(hosts.backups.list(), before, "a refusal pruned somebody's copies")
    }

    /// And an Apply that *is* attempted keeps the count at the limit rather
    /// than letting it grow without bound.
    func testAnAppliedWriteKeepsTenCopies() async throws {
        let hosts = Hosts()
        let seeded = hosts.fillTheBackups(10)
        let outcome = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(hosts.backups.list().count, 10)
        XCTAssertEqual(hosts.backups.list().first, seeded[1], "the oldest is the one that went")
    }

    /// 760 KB, which is over the ceiling however the arithmetic rounds — and
    /// every byte of it inside the base64 alphabet once encoded, so nothing
    /// else can be doing the refusing.
    private static let tooBig = String(repeating: "10.0.0.1\tbox.local\n", count: 40_000)

    // MARK: - Reading

    func testALoadAnswersWithWhatIsOnDisk() async throws {
        let state = try await loadState(Hosts().engine)
        XCTAssertEqual(state.hostsText, "127.0.0.1\tlocalhost\n")
        XCTAssertTrue(state.hostsReadable)
    }

    /// An unreadable file is not an empty file, and the page says so.
    func testAnUnreadableFileIsNotAnEmptyOne() async throws {
        let hosts = Hosts()
        hosts.file.changeUnderTheApp(to: nil)
        let state = try await loadState(hosts.engine)
        XCTAssertFalse(state.hostsReadable)
        XCTAssertEqual(state.hostsText, "")
    }

    func testALoadCarriesTheCopiesTheModuleHolds() async throws {
        let hosts = Hosts()
        _ = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        XCTAssertFalse(hosts.backups.list().isEmpty,
                       "no copies at all, so the reading proves nothing")
        let state = try await loadState(hosts.engine)
        XCTAssertEqual(state.backups, hosts.backups.list())
    }

    // MARK: - Restoring

    func testARestorePutsABackupBackThroughTheSameRoute() async throws {
        let hosts = Hosts()
        _ = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        let saved = try XCTUnwrap(hosts.backups.list().first)
        let outcome = try await restore(hosts.engine, saved)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(hosts.file.read(), "127.0.0.1\tlocalhost\n")
        XCTAssertEqual(hosts.privileged.commands.count, 2)
    }

    /// A backup id from a payload is a name from outside, so it may only ever
    /// select a copy the port already listed — never build a path.
    ///
    /// **This test alone does not prove the engine's check.** `FakeBackups` is
    /// a dictionary, and a dictionary answers nothing to `"../x"` whatever the
    /// engine does — measured, and inert with the membership check deleted. The
    /// defence that carries weight against a path is at the *port*:
    /// `SystemBackupsTests.testAnIdThatClimbsOutOfTheFolderReadsNothing` holds
    /// it against a real neighbouring file. The engine's own half is proved by
    /// the test below.
    func testARestoreOfAnUnknownBackupAsksRootNothing() async throws {
        let hosts = Hosts()
        let outcome = try await restore(hosts.engine, "../../etc/sudoers")
        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(hosts.privileged.commands.isEmpty)
    }

    /// **What the fake cannot prove, the real port can.**
    ///
    /// `SystemBackups` is not a dictionary. Its `read` gates the name and then
    /// asks the filesystem, and macOS's default APFS volume is
    /// case-*insensitive* while `contentsOfDirectory` is case-*preserving* — so
    /// a `…Z.hosts` on disk answers to `…z.hosts`, a name `list()` does not
    /// contain and `BackupName.isOurs` has no opinion about. That gap is what
    /// the engine's own membership check closes, which is why it is not the
    /// port's gate written twice.
    ///
    /// Nothing here reads `/etc/hosts` or raises a dialog: a scratch directory
    /// and a fake root.
    func testAnIdThatIsNotInTheListingIsRefusedEvenWhenTheFolderWouldAnswerIt() async throws {
        let onDisk = "2026-08-18T120000Z.hosts"
        let otherCase = "2026-08-18T120000z.hosts"
        let backups = SystemBackups(directory: scratchDirectory("hosts-restore-case"))
        XCTAssertTrue(backups.save("127.0.0.1\tlocalhost\n", name: onDisk))
        try XCTSkipUnless(backups.read(otherCase) != nil,
                          "this volume is case-sensitive, so the folder refuses it first")
        XCTAssertFalse(backups.list().contains(otherCase), "the listing is not case-preserving")

        let file = FakeHostsFile()
        let privileged = FakePrivileged(.succeed, writingTo: file)
        let engine = HostsEngine(file: file, privileged: privileged, backups: backups,
                                 sshConfig: FakeSSHConfig(url: URL(fileURLWithPath: "/nowhere/.ssh/config"), text: "Host a\n"),
                                 knownHosts: FakeKnownHosts(), keys: FakeSSHKeys(), agent: FakeSSHAgent(),
                                 generator: FakeGenerator(),
                                 home: URL(fileURLWithPath: "/nowhere"),
                                 now: { Date(timeIntervalSince1970: 1_755_000_000) },
                                 transport: LocalTransport())
        let outcome = try await restore(engine, otherCase)
        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(privileged.commands.isEmpty, "a copy nobody listed reached the dialog")
    }

    /// Listed, and gone or not UTF-8 by the time it is asked for. A folder
    /// loses files; a copy that will not decode must not be written back as
    /// root, and must not reach the dialog to be refused after it.
    func testABackupThatWillNotReadBackIsNeverHandedToRoot() async throws {
        let hosts = Hosts()
        _ = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        let saved = try XCTUnwrap(hosts.backups.list().first)
        hosts.backups.makeUnreadable(saved)
        let outcome = try await restore(hosts.engine, saved)
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(hosts.privileged.commands.count, 1, "the unreadable copy reached the dialog")
        XCTAssertEqual(hosts.file.read(), "10.0.0.1\tbox\n")
    }

    // MARK: - While the dialog is up

    /// **Asserted as a call that has *not* returned, not as one that eventually
    /// does.** The second is true of a port that never waited at all, which is
    /// what makes most busy-state tests vacuous.
    func testTheOperationSaysItIsRunningWhileTheDialogIsUp() async throws {
        let hosts = Hosts()
        hosts.privileged.pausesUntilAnswered()
        let events = Collected(hosts.transport)
        defer { events.stop() }

        let engine = hosts.engine
        let returned = DispatchSemaphore(value: 0)
        let applying = Task { () -> HostsOutcome in
            defer { returned.signal() }
            return try await apply(engine, "10.0.0.1\tbox\n")
        }

        XCTAssertTrue(hosts.privileged.waitForTheDialog(timeout: 5),
                      "the write never reached the dialog")
        XCTAssertEqual(returned.wait(timeout: .now() + 0.2), .timedOut,
                       "the dialog answered itself, so nothing here is about being busy")
        let mid = try await events.operation(timeout: 5)
        XCTAssertTrue(mid.running)
        XCTAssertNil(mid.lastOutcome, "an operation still in the dialog already has a verdict")

        hosts.privileged.answerTheDialog()
        let outcome = try await applying.value
        XCTAssertEqual(outcome, .applied)
        let settled = try await events.operation(where: { !$0.running }, timeout: 5)
        XCTAssertEqual(settled.lastOutcome, .applied)
    }

    /// The state goes out again when the write is over — the transport replays
    /// per name, so a page opened afterwards finds the file it now has rather
    /// than the one it had.
    func testTheStateGoesOutAgainWhenTheWriteIsOver() async throws {
        let hosts = Hosts()
        _ = try await apply(hosts.engine, "10.0.0.1\tbox\n")
        let events = Collected(hosts.transport)
        defer { events.stop() }
        let state = try await events.state(timeout: 5)
        XCTAssertEqual(state.hostsText, "10.0.0.1\tbox\n")
    }

    /// `activate()` emits before any view model exists, and the replay is what
    /// carries it to one built afterwards.
    func testActivatingEmitsTheStateForWhoeverSubscribesLater() async throws {
        let hosts = Hosts()
        hosts.engine.activate()
        let events = Collected(hosts.transport)
        defer { events.stop() }
        let state = try await events.state(timeout: 5)
        XCTAssertEqual(state.hostsText, "127.0.0.1\tlocalhost\n")
    }
}

/// The engine with every port named, including the transport — so that no test
/// here can reach a default that talks to the machine. Eleven Autopilot tests
/// took a defaulted port's real keychain and rolled the owner's rules back;
/// this module's defaults are `/etc/hosts` and a password dialog.
private final class Hosts {
    let file = FakeHostsFile()
    let backups = FakeBackups()
    let privileged: FakePrivileged
    let transport = LocalTransport()
    let engine: HostsEngine

    init(_ behaviour: FakePrivileged.Behaviour = .succeed) {
        privileged = FakePrivileged(behaviour, writingTo: file)
        engine = HostsEngine(file: file, privileged: privileged, backups: backups,
                             sshConfig: FakeSSHConfig(url: URL(fileURLWithPath: "/nowhere/.ssh/config"), text: "Host a\n"),
                             knownHosts: FakeKnownHosts(), keys: FakeSSHKeys(), agent: FakeSSHAgent(),
                             generator: FakeGenerator(),
                             // Every ssh port here is at `/nowhere`, and the home
                             // the gate compares them against says so too — a
                             // defaulted `home:` would be this Mac's.
                             home: URL(fileURLWithPath: "/nowhere"),
                             now: { Date(timeIntervalSince1970: 1_755_000_000) },
                             transport: transport)
    }

    /// A history already at the limit, oldest first, so that what a prune takes
    /// — or does not take — is visible.
    @discardableResult
    func fillTheBackups(_ count: Int) -> [String] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let names = (0..<count).map { BackupName.name(at: start.addingTimeInterval(Double($0))) }
        for (step, name) in names.enumerated() { _ = backups.save("copy \(step)", name: name) }
        return names
    }
}

/// Everything the engine has said, readable by name.
///
/// Subscribing happens in `init`, synchronously: `LocalTransport.events`
/// registers under its own lock and replays the last event per name there and
/// then, so nothing emitted before the pump task starts is lost — the stream
/// buffers it.
///
/// The pump task captures the box and never the collector, so `deinit` can run.
/// A `for await` that captured `self` would hold it for the life of the process
/// however weakly it was written, because the capture is only weak until the
/// method starts.
private final class Collected {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [EngineEvent] = []
        func append(_ event: EngineEvent) { lock.withLock { events.append(event) } }
        var all: [EngineEvent] { lock.withLock { events } }
    }

    private let box = Box()
    private let pump: Task<Void, Never>

    init(_ transport: LocalTransport) {
        let box = self.box
        let stream = transport.events
        pump = Task { for await event in stream { box.append(event) } }
    }

    func stop() { pump.cancel() }
    deinit { pump.cancel() }

    func operation(where matches: (HostsOperation) -> Bool = { _ in true },
                   timeout: TimeInterval) async throws -> HostsOperation {
        try await first(.operation, as: HostsOperation.self, where: matches, timeout: timeout)
    }

    func state(timeout: TimeInterval) async throws -> HostsState {
        try await first(.state, as: HostsState.self, where: { _ in true }, timeout: timeout)
    }

    /// Polled against a deadline rather than awaited off the stream, so a test
    /// whose event never arrives fails rather than hanging the suite.
    private func first<T: Decodable>(_ name: HostsEvent, as type: T.Type,
                                     where matches: (T) -> Bool,
                                     timeout: TimeInterval) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for event in box.all where event.name == name.rawValue {
                if let value = try? JSONDecoder().decode(type, from: event.payload),
                   matches(value) { return value }
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        } while Date() < deadline
        throw NoSuchEvent(name: name.rawValue)
    }
}

private struct NoSuchEvent: Error { let name: String }

/// Sent the way a view model sends it, and outside the test case so that a
/// `Task` in a test never has to capture the case itself.
private func apply(_ engine: HostsEngine, _ text: String) async throws -> HostsOutcome {
    let payload = try JSONEncoder().encode(HostsApply(text: text))
    let reply = try await engine.transport.send(
        EngineCommand(name: HostsCommand.applyHosts.rawValue, payload: payload))
    return try JSONDecoder().decode(HostsOutcome.self, from: reply)
}

private func restore(_ engine: HostsEngine, _ backupID: String) async throws -> HostsOutcome {
    let payload = try JSONEncoder().encode(HostsRestore(backupID: backupID))
    let reply = try await engine.transport.send(
        EngineCommand(name: HostsCommand.restoreHosts.rawValue, payload: payload))
    return try JSONDecoder().decode(HostsOutcome.self, from: reply)
}

/// Not `load`: `XCTestCase` inherits `NSObject.load()`, and an unqualified call
/// finds that one instead.
private func loadState(_ engine: HostsEngine) async throws -> HostsState {
    let reply = try await engine.transport.send(
        EngineCommand(name: HostsCommand.load.rawValue))
    return try JSONDecoder().decode(HostsState.self, from: reply)
}

/// The promise `HostsState.init(from:)` is written by hand to keep.
///
/// A stored default does **not** make an older payload decode: Swift's
/// synthesised `Decodable` wants the key regardless, and `JSONDecoder` abandons
/// the whole document rather than filling in the one field — every screen then
/// holds stale defaults. `KeepAwakeEngine.StatePayload` carried three comments
/// claiming otherwise and none of them was true, which is why this is a test
/// and not a sentence.
final class HostsStateDecodingTests: XCTestCase {

    func testAPayloadFromBeforeTheCopiesShippedStillDecodes() throws {
        let older = Data(#"{"hostsText":"127.0.0.1\tlocalhost\n","hostsReadable":true}"#.utf8)
        let state = try JSONDecoder().decode(HostsState.self, from: older)
        XCTAssertEqual(state.hostsText, "127.0.0.1\tlocalhost\n")
        XCTAssertTrue(state.hostsReadable)
        XCTAssertEqual(state.backups, [])
    }

    /// The other half: a field that is *not* optional stays required, so a
    /// payload missing the file itself is a failure rather than an empty file
    /// quietly reported as the truth.
    func testAPayloadMissingTheFileIsRefusedRatherThanReadAsEmpty() {
        let broken = Data(#"{"hostsReadable":true,"backups":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(HostsState.self, from: broken))
    }

    func testAWholePayloadSurvivesTheRoundTrip() throws {
        let state = HostsState(hostsText: "::1\tlocalhost\n", hostsReadable: false,
                               backups: ["2026-08-18T120000Z.hosts"])
        let back = try JSONDecoder().decode(HostsState.self,
                                            from: try JSONEncoder().encode(state))
        XCTAssertEqual(back, state)
    }
}
