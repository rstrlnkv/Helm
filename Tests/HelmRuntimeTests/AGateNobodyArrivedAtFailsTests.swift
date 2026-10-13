import HelmTestSupport
import XCTest

/// A gate that nobody arrives at fails the test that waited on it, at the line that waited.
///
/// `PromptGate.reached` is the precondition of every test that asserts an absence after a prompt: the
/// absence only means something once the prompt is known to have stood. A wait that comes back quietly when
/// the prompt never came turns each of those tests into a claim about a system that never got there, and it
/// passes.
///
/// The failure `reached` records is caught here instead of failing the row, and only for the span of the one
/// call: the case overrides `record`, keeps what the call recorded and does not pass it on, then stops
/// listening before the row asserts anything. The row's own assertions fail as they would anywhere, and so
/// does anything recorded outside that span. `record` and not `XCTExpectFailure`, which belongs to a
/// thread: a wait that suspends comes back on another one, and the expectation is gone, so the same call was
/// caught on one run and not on the next.
///
/// The row that names the line calls `reached` on a line that also reads `#line`, because the line is what
/// it holds. The default-deadline row holds the wait between 1.5 and 5 seconds:
/// shorter is no wait for a prompt macOS may be slow to put up, longer turns a red into a run nobody reads.
///
/// Total failure of the subject prints three different things. A `reached` that returns quietly fails the
/// three nobody-arrives rows, each saying it returned after so many seconds with no failure recorded. One
/// that fails inside the helper, at its own line, fails the row that names the line, and shows the file it
/// landed in. One that fails at once, without waiting, fails the late-arrival row for the time it took and
/// for the failure it recorded about a prompt that came.
final class AGateNobodyArrivedAtFailsTests: XCTestCase {

    private let heard = RecordedFailures()

    override func record(_ issue: XCTIssue) {
        guard !heard.take(issue) else { return }
        super.record(issue)
    }

    // MARK: - Nobody arrives

    func testAGateNobodyArrivedAtRecordsAFailure() async {
        let gate = PromptGate()

        heard.startListening()
        let started = ContinuousClock.now
        await gate.reached(within: 0.1)
        let took = shown(since: started)
        let failures = await stopListening()

        XCTAssertFalse(failures.isEmpty,
                       "reached returned quietly after \(took) s with nobody at the gate, and recorded no "
                       + "failure: a test that waits on it goes on to assert about a prompt that never came")
    }

    func testTheFailureLandsOnTheLineThatAsked() async {
        let gate = PromptGate()
        var askedAt: UInt = 0

        heard.startListening()
        let started = ContinuousClock.now
        askedAt = #line; await gate.reached(within: 0.1)
        let took = shown(since: started)
        let failures = await stopListening()

        let here = URL(fileURLWithPath: #filePath).standardized.path
        XCTAssertEqual(failures, [RecordedFailure(path: here, line: Int(askedAt))],
                       "after \(took) s the failures were \(failures.map { "\($0.path):\($0.line)" }), "
                       + "and the one wanted is this file at line \(askedAt), where reached was called")
    }

    func testTheDefaultDeadlineIsLongEnoughToWaitForAndEndsInAFailure() async {
        let gate = PromptGate()

        heard.startListening()
        let started = ContinuousClock.now
        await gate.reached()
        let took = shown(since: started)
        let failures = await stopListening()

        XCTAssertFalse(failures.isEmpty,
                       "reached() returned quietly after \(took) s with nobody at the gate, and recorded "
                       + "no failure")
        XCTAssertGreaterThanOrEqual(Double(took) ?? 0, 1.5,
                                    "reached() gave up after \(took) s, which is not a wait for a prompt "
                                    + "that macOS may take a moment to put up")
        XCTAssertLessThanOrEqual(Double(took) ?? .infinity, 5.0,
                                 "reached() waited \(took) s for a prompt that never came, and a wait that "
                                 + "long turns a red into a run nobody reads")
    }

    // MARK: - Somebody arrives

    /// The two rows below listen for a failure too and want none heard: a failure from `reached` is then
    /// named by the row, and cannot land from the main thread after the row is over.
    func testAGateSomebodyArrivedAtReturnsAtOnceAndRecordsNothing() async {
        let gate = PromptGate()
        let prompt = Task { await gate.arrive() }
        await grace(0.05)

        heard.startListening()
        let started = ContinuousClock.now
        await gate.reached()
        let took = shown(since: started)
        let failures = await stopListeningAfterAWhile()

        XCTAssertEqual(failures, [], "reached recorded a failure about a prompt that was up")
        XCTAssertLessThan(Double(took) ?? .infinity, 1.0,
                          "reached took \(took) s to see a prompt that was already up: it waited for "
                          + "something other than the prompt")
        await gate.open()
        await prompt.value
    }

    func testAnArrivalInsideTheDeadlineIsWaitedFor() async {
        let gate = PromptGate()
        let prompt = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await gate.arrive()
        }

        heard.startListening()
        let started = ContinuousClock.now
        await gate.reached(within: 3)
        let took = shown(since: started)
        let failures = await stopListeningAfterAWhile()

        XCTAssertEqual(failures, [], "reached recorded a failure about a prompt that stood up inside its "
                       + "deadline, after \(took) s")
        XCTAssertGreaterThanOrEqual(Double(took) ?? 0, 0.25,
                                    "reached came back after \(took) s, before a prompt that stands up "
                                    + "after 0.3 s, so it did not wait for it")
        XCTAssertLessThan(Double(took) ?? .infinity, 2.0,
                          "reached took \(took) s to see a prompt that stood up after 0.3 s")
        await gate.open()
        await prompt.value
    }

    // MARK: - Reading the clock and the failures

    /// What the call recorded. XCTest delivers an issue recorded off the main thread to `record` on the main
    /// one, and that can be after the recording call has gone on, so listening stops only once a failure has
    /// been heard and a moment has passed for a second, or after a second with none. A call that records
    /// nothing therefore costs the second here, and one that records at once costs that moment and no more.
    private func stopListening() async -> [RecordedFailure] {
        let giveUp = ContinuousClock.now + .seconds(1)
        while heard.count == 0, ContinuousClock.now < giveUp {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        if heard.count > 0 { await grace(0.05) }
        return heard.stopListening()
    }

    /// What a call that should have recorded nothing recorded, once the main thread has had a fifth of a
    /// second to deliver it.
    private func stopListeningAfterAWhile() async -> [RecordedFailure] {
        await grace(0.2)
        return heard.stopListening()
    }

    /// Seconds since `start`, to two places, as the text the messages print and the rows compare.
    private func shown(since start: ContinuousClock.Instant) -> String {
        let parts = start.duration(to: .now).components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        return String(format: "%.2f", seconds)
    }
}

private struct RecordedFailure: Equatable {
    let path: String
    let line: Int
}

/// Written from whatever thread records the failure and read from the test's own, so it holds a lock.
private final class RecordedFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var listening = false
    private var kept: [RecordedFailure] = []

    func startListening() {
        lock.lock()
        defer { lock.unlock() }
        kept = []
        listening = true
    }

    /// True while listening, which is the case's cue not to pass the issue on.
    func take(_ issue: XCTIssue) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard listening else { return false }
        if let location = issue.sourceCodeContext.location {
            kept.append(RecordedFailure(path: location.fileURL.standardized.path,
                                        line: location.lineNumber))
        } else {
            kept.append(RecordedFailure(path: "(no location)", line: 0))
        }
        return true
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return kept.count
    }

    func stopListening() -> [RecordedFailure] {
        lock.lock()
        defer { lock.unlock() }
        listening = false
        return kept
    }
}
