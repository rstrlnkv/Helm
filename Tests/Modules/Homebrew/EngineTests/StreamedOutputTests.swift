import HelmTestSupport
import XCTest
@testable import Module_Homebrew_Engine

/// What the console shows while `brew` is working.
///
/// `stream` is the only port whose output a person reads directly, line by
/// line, as it arrives. Two ways of losing some of it silently.
final class LineBufferUTF8Tests: XCTestCase {

    /// `availableData` splits on byte boundaries, so a multi-byte character can
    /// straddle two reads, and `String(data:encoding:.utf8)` answers nil for the
    /// first chunk. Not one character of it may be lost. `brew` prints "🍺" on
    /// every successful install, and localized paths on others.
    func testACharacterSplitAcrossTwoReadsLosesNothing() {
        let sink = Locked<[String]>([])
        let buffer = LineBuffer(onLine: { line in sink.withLock { $0.append(line) } })
        let whole = Array("Poured 🍺 into the Cellar\n".utf8)
        // Cut inside the four bytes of the beer glass.
        let cut = Array("Poured 🍺".utf8).count - 2
        buffer.feed(Data(whole[..<cut]))
        buffer.feed(Data(whole[cut...]))
        XCTAssertEqual(sink.value, ["Poured 🍺 into the Cellar"])
    }

    /// The ASCII ahead of a split character survives too.
    func testTheAsciiAheadOfASplitCharacterSurvives() {
        let sink = Locked<[String]>([])
        let buffer = LineBuffer(onLine: { line in sink.withLock { $0.append(line) } })
        let whole = Array("first line\nsecond ☕ line\n".utf8)
        let cut = Array("first line\nsecond ☕".utf8).count - 1
        buffer.feed(Data(whole[..<cut]))
        buffer.feed(Data(whole[cut...]))
        XCTAssertEqual(sink.value, ["first line", "second ☕ line"])
    }

    /// A byte sequence that is not UTF-8 at all must not stall the buffer
    /// forever waiting for a continuation that never comes — the lines around
    /// it are still somebody's log.
    func testInvalidBytesDoNotSwallowTheLinesAroundThem() {
        let sink = Locked<[String]>([])
        let buffer = LineBuffer(onLine: { line in sink.withLock { $0.append(line) } })
        buffer.feed(Data("before\n".utf8) + Data([0xFF, 0xFE]) + Data("\nafter\n".utf8))
        buffer.flush()
        XCTAssertEqual(sink.value.first, "before")
        XCTAssertEqual(sink.value.last, "after")
    }

    /// Plain ASCII, unsplit: the control that proves the above are about the
    /// boundary and not about the buffer generally.
    func testWholeLinesArriveInOrder() {
        let sink = Locked<[String]>([])
        let buffer = LineBuffer(onLine: { line in sink.withLock { $0.append(line) } })
        buffer.feed(Data("a\nb\n".utf8))
        buffer.feed(Data("c\n".utf8))
        XCTAssertEqual(sink.value, ["a", "b", "c"])
    }

    /// A last line with no newline is still a line.
    func testFlushEmitsTheTrailingPartialLine() {
        let sink = Locked<[String]>([])
        let buffer = LineBuffer(onLine: { line in sink.withLock { $0.append(line) } })
        buffer.feed(Data("no newline here".utf8))
        XCTAssertEqual(sink.value, [])
        buffer.flush()
        XCTAssertEqual(sink.value, ["no newline here"])
    }
}

/// The other half: what is still in the pipe when the child exits.
final class StreamTailTests: XCTestCase {

    /// What the child wrote and the reader has not picked up yet when it exits
    /// is still delivered: a pipe holds tens of kilobytes, and what a tool
    /// writes last is its summary, such as the `🍺 /opt/homebrew/Cellar/…` line.
    ///
    /// **The consumer has to be slower than the producer, or this passes by
    /// luck.** With an instant `onLine` the reader keeps up and the pipe is empty
    /// at the exit. The real consumer is slow (a hop to the main actor, a
    /// `@Published` append, a redraw), so the delay is the shape of the only
    /// caller. Asserted on the *last* line and the count: the head always
    /// arrives.
    func testTheLastLineOfABurstIsNotLost() {
        let count = 5000
        let sink = Locked<[String]>([])
        let done = DispatchSemaphore(value: 0)
        ShellProcessRunner().stream(
            "/bin/sh",
            ["-c", "i=0; while [ $i -lt \(count) ]; do echo \"line$i\"; i=$((i+1)); done"],
            env: [:],
            onLine: { line in
                sink.withLock { $0.append(line) }
                // Stand in for the main-actor hop the real console pays.
                if line.hasSuffix("00") { usleep(2000) }
            },
            onExit: { _ in done.signal() })
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success, "stream never reported an exit")
        XCTAssertEqual(sink.value.last, "line\(count - 1)",
                       "the tail was discarded at exit (\(sink.value.count) of \(count) lines arrived)")
        XCTAssertEqual(sink.value.count, count)
    }

    /// The exit status is what tells the page whether the operation worked, so
    /// draining must not cost it.
    func testTheExitStatusStillArrives() {
        let done = DispatchSemaphore(value: 0)
        let box = Locked<Int32?>(nil)
        ShellProcessRunner().stream("/bin/sh", ["-c", "echo out; exit 17"], env: [:],
                                    onLine: { _ in },
                                    onExit: { box.value = $0; done.signal() })
        XCTAssertEqual(done.wait(timeout: .now() + 30), .success)
        XCTAssertEqual(box.value, 17)
    }

    /// A command that cannot be launched at all still has to report, or the
    /// page keeps its spinner forever.
    func testAnUnlaunchableCommandReportsAFailure() {
        let done = DispatchSemaphore(value: 0)
        let box = Locked<Int32?>(nil)
        ShellProcessRunner().stream("/nonexistent/tool", [], env: [:],
                                    onLine: { _ in },
                                    onExit: { box.value = $0; done.signal() })
        XCTAssertEqual(done.wait(timeout: .now() + 30), .success, "nothing reported an exit")
        XCTAssertEqual(box.value, -1)
    }
}
