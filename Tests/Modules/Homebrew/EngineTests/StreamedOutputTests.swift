import XCTest
@testable import Module_Homebrew_Engine

/// What the console shows while `brew` is working.
///
/// `stream` is the only port whose output a person reads directly, line by
/// line, as it arrives. Two ways of losing some of it, both silent.
final class LineBufferUTF8Tests: XCTestCase {

    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }
        func take(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
    }

    /// The trap: `availableData` splits on byte boundaries, not character
    /// boundaries, so a multi-byte character straddling two reads leaves the
    /// first chunk ending mid-sequence. `String(data:encoding:.utf8)` answers
    /// nil for that, and the whole chunk — not the one character — was dropped
    /// on the floor.
    ///
    /// Reachable with any non-ASCII output past one read. `brew` prints "🍺"
    /// on every successful install and localized paths on plenty of others.
    func testACharacterSplitAcrossTwoReadsLosesNothing() {
        let sink = Sink()
        let buffer = LineBuffer(onLine: { sink.take($0) })
        let whole = Array("Poured 🍺 into the Cellar\n".utf8)
        // Cut inside the four bytes of the beer glass.
        let cut = Array("Poured 🍺".utf8).count - 2
        buffer.feed(Data(whole[..<cut]))
        buffer.feed(Data(whole[cut...]))
        XCTAssertEqual(sink.lines, ["Poured 🍺 into the Cellar"])
    }

    /// The same defect one layer out: everything before the split character is
    /// ASCII and perfectly decodable, and it went too.
    func testTheAsciiAheadOfASplitCharacterSurvives() {
        let sink = Sink()
        let buffer = LineBuffer(onLine: { sink.take($0) })
        let whole = Array("first line\nsecond ☕ line\n".utf8)
        let cut = Array("first line\nsecond ☕".utf8).count - 1
        buffer.feed(Data(whole[..<cut]))
        buffer.feed(Data(whole[cut...]))
        XCTAssertEqual(sink.lines, ["first line", "second ☕ line"])
    }

    /// A byte sequence that is not UTF-8 at all must not stall the buffer
    /// forever waiting for a continuation that never comes — the lines around
    /// it are still somebody's log.
    func testInvalidBytesDoNotSwallowTheLinesAroundThem() {
        let sink = Sink()
        let buffer = LineBuffer(onLine: { sink.take($0) })
        buffer.feed(Data("before\n".utf8) + Data([0xFF, 0xFE]) + Data("\nafter\n".utf8))
        buffer.flush()
        XCTAssertEqual(sink.lines.first, "before")
        XCTAssertEqual(sink.lines.last, "after")
    }

    /// Plain ASCII, unsplit: the control that proves the above are about the
    /// boundary and not about the buffer generally.
    func testWholeLinesArriveInOrder() {
        let sink = Sink()
        let buffer = LineBuffer(onLine: { sink.take($0) })
        buffer.feed(Data("a\nb\n".utf8))
        buffer.feed(Data("c\n".utf8))
        XCTAssertEqual(sink.lines, ["a", "b", "c"])
    }

    /// A last line with no newline is still a line.
    func testFlushEmitsTheTrailingPartialLine() {
        let sink = Sink()
        let buffer = LineBuffer(onLine: { sink.take($0) })
        buffer.feed(Data("no newline here".utf8))
        XCTAssertEqual(sink.lines, [])
        buffer.flush()
        XCTAssertEqual(sink.lines, ["no newline here"])
    }
}

/// The other half: what is still in the pipe when the child exits.
final class StreamTailTests: XCTestCase {

    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }
        func take(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
    }

    /// The trap: `terminationHandler` cleared the readability handler and
    /// reported the exit at once. A pipe holds tens of kilobytes, so whatever
    /// the child had written and the reader had not picked up yet was thrown
    /// away — and what a tool writes last is its summary. The
    /// `🍺 /opt/homebrew/Cellar/…` line at the end of an install is exactly the
    /// line somebody is waiting for.
    ///
    /// **The consumer has to be slower than the producer, or this passes by
    /// luck.** Measured before the fix: 5000 lines with an instant `onLine`
    /// arrived complete in 5 runs out of 5, because the reader kept up and the
    /// pipe was empty by the time the child exited. The same 5000 lines with a
    /// consumer taking 2 ms a chunk lost the tail in 5 runs out of 5 — between
    /// 396 and 458 lines each time. The real consumer is the slow one: `onLine`
    /// emits an event that hops to the main actor, appends to a `@Published`
    /// array and redraws a scrolling console. So the delay here is not a
    /// contrivance to force a failure, it is the shape of the only caller.
    ///
    /// Asserted on the *last* line and on the count, never on "some output
    /// arrived": the head of the stream always arrives, which is what made this
    /// invisible.
    func testTheLastLineOfABurstIsNotLost() {
        let count = 5000
        let sink = Sink()
        let done = DispatchSemaphore(value: 0)
        ShellProcessRunner().stream(
            "/bin/sh",
            ["-c", "i=0; while [ $i -lt \(count) ]; do echo \"line$i\"; i=$((i+1)); done"],
            env: [:],
            onLine: { line in
                sink.take(line)
                // Stand in for the main-actor hop the real console pays.
                if line.hasSuffix("00") { usleep(2000) }
            },
            onExit: { _ in done.signal() })
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success, "stream never reported an exit")
        XCTAssertEqual(sink.lines.last, "line\(count - 1)",
                       "the tail was discarded at exit (\(sink.lines.count) of \(count) lines arrived)")
        XCTAssertEqual(sink.lines.count, count)
    }

    /// The exit status is what tells the page whether the operation worked, so
    /// draining must not cost it.
    func testTheExitStatusStillArrives() {
        let done = DispatchSemaphore(value: 0)
        let box = StatusBox()
        ShellProcessRunner().stream("/bin/sh", ["-c", "echo out; exit 17"], env: [:],
                                    onLine: { _ in },
                                    onExit: { box.status = $0; done.signal() })
        XCTAssertEqual(done.wait(timeout: .now() + 30), .success)
        XCTAssertEqual(box.status, 17)
    }

    /// A command that cannot be launched at all still has to report, or the
    /// page keeps its spinner forever.
    func testAnUnlaunchableCommandReportsAFailure() {
        let done = DispatchSemaphore(value: 0)
        let box = StatusBox()
        ShellProcessRunner().stream("/nonexistent/tool", [], env: [:],
                                    onLine: { _ in },
                                    onExit: { box.status = $0; done.signal() })
        XCTAssertEqual(done.wait(timeout: .now() + 30), .success, "nothing reported an exit")
        XCTAssertEqual(box.status, -1)
    }

    private final class StatusBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int32?
        var status: Int32? {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }
}
