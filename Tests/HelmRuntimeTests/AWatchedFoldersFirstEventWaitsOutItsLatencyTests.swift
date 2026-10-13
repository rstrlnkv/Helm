import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// `FolderWatcher.Sink.start` asks FSEvents for a second of latency, and its
/// comment says what that is for: a download in progress writes many times, and
/// acting on the first write would move a half-written file.
///
/// The stream is created without `kFSEventStreamCreateFlagNoDefer`, which in
/// FSEvents' own header changes what the latency means: with the flag, after a
/// quiet spell the first event is delivered at once and only the ones behind it
/// wait. The watcher's comment says the first write waits out that second too;
/// whether it does is read off a stream that is running.
///
/// **The write is made by another process.** The stream carries
/// `kFSEventStreamCreateFlagIgnoreSelf`, so a file this process writes raises no
/// event, and a test that wrote it itself would wait for nothing. The clock is
/// read just before the writer is launched, which is earlier than the write, so
/// the time counted here is longer than the time since the write: a stream that
/// really holds an event back for its latency cannot be reported as early.
final class AWatchedFoldersFirstEventWaitsOutItsLatencyTests: XCTestCase {

    /// What the comment promises, and the least a first delivery may take.
    /// A tenth of a second under the second asked for, so the clock's own slack
    /// is never what fails the case; a delivery at once arrives in a small
    /// fraction of that.
    private let leastSeconds: TimeInterval = 0.9

    /// Every call the watcher made, with the clock it was made at.
    private final class Arrivals: @unchecked Sendable {
        struct Call { let at: UInt64 }

        private let lock = NSLock()
        private var all: [Call] = []
        private var firstNaming: Call?
        private let leaf: String
        /// Signalled once, by the first call that names the written file.
        let named = DispatchSemaphore(value: 0)

        init(leaf: String) { self.leaf = leaf }

        func record(_ paths: [String]) {
            let call = Call(at: DispatchTime.now().uptimeNanoseconds)
            lock.lock()
            all.append(call)
            let first = firstNaming == nil
                && paths.contains { ($0 as NSString).lastPathComponent == leaf }
            if first { firstNaming = call }
            lock.unlock()
            if first { named.signal() }
        }

        var calls: [Call] { lock.lock(); defer { lock.unlock() }; return all }
        var firstNamingTheFile: Call? { lock.lock(); defer { lock.unlock() }; return firstNaming }
    }

    private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Bool?
        func set(_ value: Bool) { lock.lock(); stored = value; lock.unlock() }
        var value: Bool? { lock.lock(); defer { lock.unlock() }; return stored }
    }

    private struct Measured {
        /// From just before the writer was launched to the first call that
        /// named its file.
        let seconds: TimeInterval
        /// How long the writer took to exit, which is how much of `seconds` was
        /// spent before the write could have finished.
        let writerSeconds: TimeInterval
        let callbacks: Int
    }

    private func seconds(from start: UInt64, to end: UInt64) -> TimeInterval {
        TimeInterval(Int64(bitPattern: end &- start)) / 1_000_000_000
    }

    /// One write by another process into a folder that is being watched, and the
    /// time until the watcher first says so. Nil, with the failure already
    /// recorded in words of its own, if the stream did not start, the writer
    /// failed, or nothing named the file within ten seconds — each of which is a
    /// different thing from an event that came too soon.
    private func firstDeliveryOfAWrite() -> Measured? {
        let root = scratchDirectory("watcher-latency")
        let leaf = "written-\(UUID().uuidString).txt"
        let arrivals = Arrivals(leaf: leaf)
        let watcher = FolderWatcher { arrivals.record($0) }
        defer { watcher.stop() }

        let answer = Answer()
        let said = DispatchSemaphore(value: 0)
        watcher.watch([root.path]) { ok in answer.set(ok); said.signal() }
        guard said.wait(timeout: .now() + 5) == .success, answer.value == true else {
            XCTFail("precondition: the stream over a real folder did not start, so nothing below measures it")
            return nil
        }

        let began = DispatchTime.now().uptimeNanoseconds
        let writer = HelmProcess.run(
            "/bin/sh", ["-c", "printf 'half a download' > \"$1\"", "sh",
                        root.appendingPathComponent(leaf).path],
            timeout: 10)
        let ended = DispatchTime.now().uptimeNanoseconds
        guard writer.status == 0 else {
            XCTFail("precondition: the writer exited with \(writer.status), so no file was written")
            return nil
        }

        guard arrivals.named.wait(timeout: .now() + 10) == .success,
              let first = arrivals.firstNamingTheFile else {
            XCTFail("""
                nothing named the written file within 10 s of the write; \
                the watcher made \(arrivals.calls.count) call(s), so this is a \
                delivery that never came and not one that came too soon
                """)
            return nil
        }
        let measured = Measured(seconds: seconds(from: began, to: first.at),
                                writerSeconds: seconds(from: began, to: ended),
                                callbacks: arrivals.calls.count)
        print(String(format: "[first delivery] %.1f ms after the writer was launched; the writer took %.1f ms; %d call(s) so far",
                     measured.seconds * 1000, measured.writerSeconds * 1000, measured.callbacks))
        return measured
    }

    /// The subject: a write by another process is delivered at all, and by a
    /// call that comes after the writer was launched. Without this the case
    /// below could be red because the harness saw nothing.
    func testAWriteByAnotherProcessIsDelivered() throws {
        guard let measured = firstDeliveryOfAWrite() else { return }
        XCTAssertGreaterThan(measured.seconds, 0,
                             "the call that named the file came before the writer was launched")
    }

    /// What the comment promises: the first delivery is not at once.
    func testTheFirstDeliveryComesNoSoonerThanTheStreamsLatency() throws {
        guard let measured = firstDeliveryOfAWrite() else { return }
        XCTAssertGreaterThanOrEqual(measured.seconds, leastSeconds, """
            the first change was delivered \(Int(measured.seconds * 1000)) ms after the \
            write began, against the \(Int(leastSeconds * 1000)) ms this must take; the \
            stream is asked to wait 1000 ms so that a download still being written is \
            not seen half done
            """)
    }
}
