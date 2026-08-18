import XCTest
import Combine
import HelmContract
import HelmTestSupport
import HelmRuntime
import HelmUI
import Module_Hosts_Engine
@testable import Module_Hosts_UI

@MainActor
final class HostsViewModelTests: XCTestCase {

    private let localhost = "127.0.0.1\tlocalhost\n"

    /// The wire, and the model built on it. The engine is held for the test's
    /// life: it wires the transport's handler with `[weak self]`.
    private struct Wire {
        let hosted: HostsUIWire
        let model: HostsViewModel
        var transport: LocalTransport { hosted.transport }
        var privileged: FixedPrivileged { hosted.privileged }
    }

    private func wire(file: String? = "127.0.0.1\tlocalhost\n",
                      privileged: PrivilegedOutcome = .declined,
                      backups: [String: String] = [:]) -> Wire {
        let hosted = HostsUIWire.make(file: file, privileged: privileged, backups: backups)
        let model = HostsViewModel(vm: hosted.vm)
        addTeardownBlock { await MainActor.run { model.stop() } }
        return Wire(hosted: hosted, model: model)
    }

    /// A model with its first load already over, so a test that counts
    /// something is not racing the load that fills it. **Hold and await
    /// whatever moves before counting what it moves.**
    private func loaded(file: String? = "127.0.0.1\tlocalhost\n",
                        privileged: PrivilegedOutcome = .declined,
                        backups: [String: String] = [:]) async -> Wire {
        let wired = wire(file: file, privileged: privileged, backups: backups)
        await wired.model.firstLoad?.value
        await waitUntil("the first snapshot arrived") {
            wired.model.onDisk == (file ?? "")
                && wired.model.readable == (file != nil)
                && wired.model.backups == backups.keys.sorted()
        }
        return wired
    }

    // MARK: - One file, two views of it

    /// The text is canonical. A table edit must be visible in the raw view
    /// immediately, or the two are two files.
    func testATableEditIsVisibleInTheText() async {
        let m = await loaded().model
        m.setText("127.0.0.1\tlocalhost\n10.0.0.1\tbox\n")
        let edit = m.setEnabled(false, entry: 1)
        XCTAssertEqual(edit, .applied)
        XCTAssertTrue(m.text.contains("# 10.0.0.1\tbox"), m.text)
    }

    /// And the other direction: typing in the raw view re-derives the table.
    func testTextTypedByHandIsVisibleInTheTable() async {
        let m = await loaded().model
        m.setText("127.0.0.1\tlocalhost\n10.0.0.1\tbox\n")
        XCTAssertEqual(m.entries.count, 2)
        XCTAssertEqual(m.entries[1].names, ["box"])
    }

    func testThereAreNoUnsavedChangesUntilSomethingChanges() async {
        let m = await loaded().model
        XCTAssertEqual(m.text, localhost)
        XCTAssertFalse(m.hasUnsavedChanges)
        XCTAssertEqual(m.setEnabled(false, entry: 0), .applied)
        XCTAssertTrue(m.hasUnsavedChanges)
    }

    /// Reverting means the file as it is on disk, not the file as it was when
    /// the page opened.
    func testRevertingReturnsToWhatDiskSays() async {
        let m = await loaded().model
        m.setText("nonsense\n")
        XCTAssertTrue(m.hasUnsavedChanges)
        m.revert()
        XCTAssertEqual(m.text, localhost)
        XCTAssertFalse(m.hasUnsavedChanges)
    }

    /// A state arriving from the engine while the person is mid-edit must not
    /// take their typing away. It updates what «revert» means and nothing else.
    ///
    /// **The snapshot is asserted to have landed first.** «The typing survived»
    /// is an absence, and an absence passes when the subject never happened —
    /// an `adopt` that returned early while dirty would leave the typing
    /// standing for the wrong reason.
    func testAnIncomingStateDoesNotDiscardUnsavedTyping() async {
        let m = await loaded().model
        m.setText("10.0.0.1\tmine\n")
        let somebodyElse = localhost + "192.168.0.1\tsomebody-else\n"
        m.adopt(HostsState(hostsText: somebodyElse, hostsReadable: true, backups: ["copy"]))

        XCTAssertEqual(m.onDisk, somebodyElse, "the snapshot never landed, so this test proves nothing")
        XCTAssertEqual(m.backups, ["copy"])
        XCTAssertEqual(m.text, "10.0.0.1\tmine\n")
        XCTAssertTrue(m.hasUnsavedChanges)
        // And «revert» now means the newer file, not the one the page opened on.
        m.revert()
        XCTAssertEqual(m.text, somebodyElse)
    }

    /// The other half of the same rule: a snapshot for a page nobody has
    /// touched *is* adopted, or the page would sit on a stale file for ever.
    func testAnIncomingStateReachesAPageNobodyHasTouched() async {
        let m = await loaded().model
        m.adopt(HostsState(hostsText: "10.0.0.1\tbox\n", hostsReadable: true, backups: []))
        XCTAssertEqual(m.text, "10.0.0.1\tbox\n")
        XCTAssertFalse(m.hasUnsavedChanges)
    }

    /// Each editor reaches the one it is named for. They are one line each over
    /// `HostsFile`, which is where the behaviour is tested — what is tested here
    /// is that `remove` removes rather than doing whatever the line above it did.
    func testRemovingAnEntryTakesItOutOfTheFile() async {
        let m = await loaded().model
        m.setText(localhost + "10.0.0.1\tbox\n")
        XCTAssertEqual(m.remove(entry: 0), .applied)
        XCTAssertEqual(m.entries.map(\.address), ["10.0.0.1"])
        XCTAssertFalse(m.text.contains("localhost"))
    }

    func testAppendingAnEntryPutsARowAtTheEnd() async {
        let m = await loaded().model
        XCTAssertEqual(m.append(address: "10.0.0.1", names: ["box"]), .applied)
        XCTAssertEqual(m.entries.map(\.address), ["127.0.0.1", "10.0.0.1"])
        XCTAssertTrue(m.text.hasSuffix("10.0.0.1\tbox\n"), m.text)
    }

    /// And an append Helm cannot write leaves the file exactly as it was — the
    /// gate is the engine's, and this is the hop it has to survive.
    func testAppendingARowHelmCannotWriteIsRefused() async {
        let m = await loaded().model
        XCTAssertEqual(m.append(address: "10.0.0.1", names: ["two names"]),
                       .refused(.unwritableName))
        XCTAssertEqual(m.text, localhost)
        XCTAssertEqual(m.lastRefusal, .unwritableName)
    }

    // MARK: - The refusal survives the hop

    /// An editor that declines says so to the caller *and* leaves the reason
    /// where the page can draw it. A field that snaps back with no reason given
    /// is the defect these two channels exist to prevent.
    func testARefusedEditIsReportedBothWays() async {
        let m = await loaded().model
        let edit = m.setAddress("0177.0.0.1", entry: 0)
        XCTAssertEqual(edit, .refused(.unwritableAddress))
        XCTAssertEqual(m.lastRefusal, .unwritableAddress)
        XCTAssertEqual(m.entries[0].address, "127.0.0.1")
    }

    /// And an edit that goes through clears the reason, or the page keeps
    /// explaining a refusal the person has already corrected.
    func testAnAppliedEditClearsTheReasonTheLastOneWasRefused() async {
        let m = await loaded().model
        XCTAssertEqual(m.setNames([], entry: 0), .refused(.noNames))
        XCTAssertEqual(m.lastRefusal, .noNames)
        XCTAssertEqual(m.setNames(["box"], entry: 0), .applied)
        XCTAssertNil(m.lastRefusal)
    }

    /// **A refused edit does not re-render.**
    ///
    /// It cannot be read off the text: `render(parse(x)) == x` for every file
    /// the fuzz search could think of
    /// (`HostsFuzzRoundTripTests.testFortyThousandGeneratedFilesComeBackByteForByte`),
    /// so a re-render of a document nothing changed produces the identical
    /// string — and a value assertion here would pass with the guard removed.
    /// What it does
    /// produce is an assignment to a `@Published` property — a body pass, and a
    /// binding written back under a caret that is mid-word. So the count of
    /// publications is what this measures, with an applied edit in the same
    /// test as the control that proves the counter can count.
    func testARefusedEditDoesNotPublishTheTextAgain() async {
        let m = await loaded().model
        var published = 0
        let watching = m.$text.dropFirst().sink { _ in published += 1 }
        defer { watching.cancel() }

        XCTAssertEqual(m.setEnabled(false, entry: 0), .applied)
        XCTAssertEqual(published, 1, "an applied edit must re-render, or this counter counts nothing")

        XCTAssertEqual(m.setAddress("no such address", entry: 0), .refused(.unwritableAddress))
        XCTAssertEqual(published, 1, "a refused edit re-rendered the document it declined to change")
    }

    // MARK: - The wire

    /// The load fired from `init` is **held**, and it fills the page.
    ///
    /// A load fired and forgotten leaves every later load racing it on one wire
    /// — 8 failures in 200 constructions in Autopilot before its model kept the
    /// task.
    func testTheFirstLoadIsHeldAndFillsTheModel() async {
        let wired = wire(backups: ["hosts-2026-08-18-000000": "old"])
        XCTAssertNotNil(wired.model.firstLoad, "the first load was fired and forgotten")
        await wired.model.firstLoad?.value
        await waitUntil("the snapshot arrived") { wired.model.onDisk == localhost }

        XCTAssertEqual(wired.model.text, localhost)
        XCTAssertEqual(wired.model.onDisk, localhost)
        XCTAssertTrue(wired.model.readable)
        XCTAssertEqual(wired.model.backups, ["hosts-2026-08-18-000000"])
    }

    /// A file that could not be read at all is not an empty file, and the page
    /// is told which it is.
    func testAnUnreadableFileArrivesAsUnreadableRatherThanEmpty() async {
        let m = await loaded(file: nil).model
        XCTAssertFalse(m.readable)
        XCTAssertEqual(m.text, "")
    }

    /// Apply carries **what is on screen**, not the file the page opened on,
    /// and the operation event comes back — both halves, because `applying`
    /// gates the button and `lastOutcome` is the sentence the person reads.
    ///
    /// The payload is read off the sentence root was handed: an outcome alone
    /// would be the same for an apply that sent the wrong file.
    func testApplyCarriesTheEditedTextAndTheOutcomeComesBack() async {
        let wired = await loaded(privileged: .declined)
        let edited = "10.0.0.1\tmine\n"
        wired.model.setText(edited)
        await wired.model.apply()

        XCTAssertEqual(wired.privileged.commands.count, 1, "the apply never reached the engine")
        let sentence = wired.privileged.commands[0]
        XCTAssertTrue(sentence.contains(HostsWrite.encode(edited)), "the edit was not what was sent")
        XCTAssertFalse(sentence.contains(HostsWrite.encode(localhost)),
                       "the file on disk was sent instead of the edit")

        await waitUntil("the operation finished") { wired.model.lastOutcome != nil }
        XCTAssertEqual(wired.model.lastOutcome, .declined)
        XCTAssertFalse(wired.model.applying)
    }

    /// Restore names a copy, and the copy's own bytes are what root is asked to
    /// write — the id crossed the wire, rather than the request arriving empty
    /// and the engine answering something.
    func testRestoreNamesACopyAndItsBytesAreWhatRootIsAsked() async {
        let copy = "10.0.0.1\tfrom-a-copy\n"
        let wired = await loaded(privileged: .declined,
                                 backups: ["hosts-2026-08-18-000000": copy])
        await wired.model.restore("hosts-2026-08-18-000000")

        XCTAssertEqual(wired.privileged.commands.count, 1, "the restore never reached the engine")
        XCTAssertTrue(wired.privileged.commands[0].contains(HostsWrite.encode(copy)))

        await waitUntil("the operation finished") { wired.model.lastOutcome != nil }
        XCTAssertEqual(wired.model.lastOutcome, .declined)
    }

    // MARK: - Teardown

    /// `stop()` ends the subscription, measured on the transport's own count
    /// rather than on a flag the model keeps about itself.
    ///
    /// `Task { [weak self] … }` captures weakly only at the top: once the
    /// `for await` starts it holds the object for as long as it runs, and this
    /// stream has no `.finish()`, so it runs for the life of the app. The task
    /// has to be cancelled from outside.
    func testStopEndsTheSubscription() async {
        let wired = await loaded()
        XCTAssertEqual(wired.transport.subscriberCount, 1, "the model never subscribed")

        wired.model.stop()
        await waitUntil("the subscription ended") { wired.transport.subscriberCount == 0 }
        XCTAssertEqual(wired.transport.subscriberCount, 0)
    }

}
