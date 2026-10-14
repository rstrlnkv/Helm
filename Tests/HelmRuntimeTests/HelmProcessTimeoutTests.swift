import Darwin
import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// `HelmProcess.run` blocks until the tool closes its output — which for a tool
/// that has hung (a brew waiting on another brew's lock, an installer waiting
/// for input nobody can give) is never. The caller's thread is parked for the
/// life of the process, and everything behind it queues. A deadline turns that
/// into an answer: a named status, promptly.
final class HelmProcessTimeoutTests: XCTestCase {

    /// The failure being looked for is a hang; it must be reported, not waited
    /// on. `/bin/sleep` writes nothing and exits in 30 s — far past the suite's
    /// patience, well within the machine's.
    func testAHungToolIsCutOffAtTheDeadline() {
        let started = Date()
        let result = HelmProcess.run("/bin/sleep", ["30"], timeout: 0.3)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(result.status, HelmProcess.timedOutStatus,
                       "a tool that never answered came back as something other than a timeout")
        XCTAssertLessThan(elapsed, 10,
                          "the deadline passed at 0.3 s and run returned only after \(elapsed) s")
    }

    /// The deadline is not delivered by abandoning the child: it is terminated.
    /// The shell traps TERM and leaves a marker, which is the only way to see
    /// from outside that the signal arrived. (`sleep` runs in the background and
    /// `wait` is interruptible, so the trap fires at the signal rather than
    /// after the sleep.)
    func testTheChildIsTerminatedNotAbandoned() {
        let dir = scratchDirectory("process-timeout")
        let marker = dir.appendingPathComponent("terminated")
        let script = "trap 'echo gone > \"\(marker.path)\"; exit 0' TERM; sleep 30 & wait"
        _ = HelmProcess.run("/bin/sh", ["-c", script], timeout: 0.3)
        // The trap needs a moment to write after the signal lands.
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: marker.path) {
            usleep(10_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path),
                      "the deadline passed and the child was left running")
    }

    /// A tool that answers in time is untouched: same status, same output as
    /// the deadline-free path.
    func testAToolThatAnswersInTimeIsUntouched() {
        let result = HelmProcess.run("/bin/sh", ["-c", "printf hi; exit 3"], timeout: 5)
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.output, "hi")
    }

    // MARK: - A timed-out tool and the tree it started

    /// A child that dies on TERM while a grandchild it forked still holds the
    /// write end of the pipe — the shape of a `brew` that hands its work to a
    /// helper. The child is gone when the grace ends, so a KILL addressed to
    /// its pid would reach nobody; the grandchild is what is still running,
    /// and what the caller was promised gone.
    ///
    /// The grandchild ignores TERM: one that does not is taken down with the
    /// child by the first signal (measured with the grandchild a plain
    /// `sleep 20 &`: the run returned after one second with nothing left, and
    /// the row stayed green on code that does not stop the tree). It sleeps
    /// 20 s so that it ends on its own if nothing stops it, and the row removes
    /// it by the pid the script wrote.
    ///
    /// What this row holds is the grandchild gone within three seconds of the
    /// run's returned timeout, and, through the seam that records the number
    /// each signal was addressed to, TERM then KILL, both addressed to the
    /// child's pid, which is its process group's id. The seam records the
    /// number and not the call: a `kill` to the pid records the same, and only
    /// the grandchild's death tells it from a `killpg`.
    func testATimedOutRunLeavesNothingOfItsTreeRunning() throws {
        let dir = scratchDirectory("process-timeout-tree")
        let tool = ScratchTool.script("""
            trap 'exit 0' TERM
            (trap '' TERM; exec /bin/sleep 20) &
            echo $! > "$1/grandchild"
            echo $$ > "$1/child"
            wait
            """, named: "forks-a-grandchild", in: dir)
        ScratchTool.removeAtTeardown(self, dir: dir)

        _ = HelmProcess.signalsSentForTesting()
        let result = HelmProcess.run("/bin/sh", [tool, dir.path], timeout: 1)
        let signals = HelmProcess.signalsSentForTesting()

        XCTAssertEqual(result.status, HelmProcess.timedOutStatus,
                       "the run was meant to time out; nothing below means anything otherwise")
        let child = try XCTUnwrap(ScratchTool.pid(dir.appendingPathComponent("child")),
                                  "the script never recorded its own pid")
        XCTAssertEqual(signals.map(\.signal), [SIGTERM, SIGKILL],
                       "TERM at the deadline, then KILL after the grace for the grandchild that ignores it")
        XCTAssertEqual(Set(signals.map(\.group)), [child],
                       "a signal went to something other than the child's own process group")
        let grandchild = try XCTUnwrap(ScratchTool.pid(dir.appendingPathComponent("grandchild")),
                                       "the script never recorded the grandchild")
        XCTAssertFalse(ScratchTool.isRunning(child), """
            the child was meant to die on TERM, so the KILL after the grace had \
            nobody to reach; this row is about what that leaves
            """)
        XCTAssertTrue(ScratchTool.becomesGone(grandchild, within: 3), """
            the run returned its timeout and the grandchild (pid \(grandchild)) \
            was still running three seconds later, holding the tool's pipe
            """)
    }

    /// The slot is the ceiling on tools out at once, and a timed-out run gives
    /// it back. `launchCeiling` runs fill the ceiling, each with a grandchild
    /// that ignores TERM, and each times out; one more run is then asked for,
    /// and counts from inside how many of those grandchildren are still running
    /// when it starts. That run is a tool too: the grandchildren alive plus the
    /// probe are the tools out.
    ///
    /// The grandchildren ignore TERM for the reason the row above gives. Each
    /// sleeps 20 s and is removed at teardown by the pid its script wrote.
    func testASlotComesBackOnlyWhenItsToolIsGone() throws {
        let ceiling = HelmProcess.launchCeiling
        let dir = scratchDirectory("process-timeout-slot")
        let hanging = ScratchTool.script("""
            trap 'exit 0' TERM
            (trap '' TERM; exec /bin/sleep 20) &
            echo $! > "$1/g$2"
            wait
            """, named: "forks-a-grandchild", in: dir)
        let probe = ScratchTool.script("""
            alive=0
            for f in "$1"/g*; do
                state=$(/bin/ps -o stat= -p "$(cat "$f")" 2>/dev/null)
                case "$state" in
                    ""|Z*) ;;
                    *) alive=$((alive + 1)) ;;
                esac
            done
            printf %s "$alive"
            """, named: "counts-the-grandchildren", in: dir)
        ScratchTool.removeAtTeardown(self, dir: dir)

        let statuses = StatusList()
        let group = DispatchGroup()
        for n in 0..<ceiling {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                statuses.add(HelmProcess.run("/bin/sh", [hanging, dir.path, String(n)], timeout: 1).status)
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success,
                       "the bounded runs never came back")
        XCTAssertEqual(statuses.values, Array(repeating: HelmProcess.timedOutStatus, count: ceiling),
                       "every one of the \(ceiling) runs was meant to time out")
        for n in 0..<ceiling {
            XCTAssertNotNil(ScratchTool.pid(dir.appendingPathComponent("g\(n)")),
                            "run \(n) never recorded its grandchild")
        }

        let counted = HelmProcess.run("/bin/sh", [probe, dir.path], timeout: 30)
        XCTAssertEqual(counted.status, 0, "the probe did not answer")
        let alive = try XCTUnwrap(Int(counted.output), "the probe answered \(counted.output)")
        XCTAssertLessThanOrEqual(alive + 1, ceiling, """
            one more run started with \(alive) of the timed-out tools' grandchildren \
            still running — \(alive + 1) tools out against a ceiling of \(ceiling), \
            because the slots came back while their tools were alive
            """)
    }

    /// Something outside the tool's group that holds its pipe is something Helm
    /// cannot end, so it does not count toward the ceiling: once the tool is
    /// reaped and its group is empty, the run gives its slot back as it returns.
    /// `launchCeiling` runs fill the ceiling, each starts a helper in a session
    /// of its own (a `setsid` from Perl, which `exec`s a `sleep 20`) and times
    /// out; the helpers keep the pipes. One more run, bounded at one second, is
    /// then asked for with a tool that answers at once: it starts and answers.
    ///
    /// The row above cannot see this: there the group's KILL takes the
    /// grandchildren down before `run` returns, so a slot given back at that
    /// moment is given back after the tool is gone anyway. Here nothing the
    /// run can send reaches the holders; each sleeps 20 s, and the row removes
    /// them at teardown by the pid its script wrote, as it does the others.
    func testSomethingOutsideTheGroupThatHoldsThePipeDoesNotCountTowardTheCeiling() throws {
        let dir = scratchDirectory("process-timeout-escaped")
        let hanging = ScratchTool.script("""
            trap 'exit 0' TERM
            /usr/bin/perl -e 'use POSIX; POSIX::setsid(); open(F, ">", $ARGV[0]); print F "$$\\n"; close(F); exec "/bin/sleep", "20"' "$1/e$2" &
            wait
            """, named: "starts-a-helper-of-its-own", in: dir)
        let quick = ScratchTool.script("printf hi", named: "answers-at-once", in: dir)
        ScratchTool.removeAtTeardown(self, dir: dir)

        try fillTheCeilingWithTimedOutRuns(tool: hanging, in: dir)

        let result = HelmProcess.run("/bin/sh", [quick], timeout: 1)
        XCTAssertEqual(result.status, 0, """
            one more run, asked for while \(HelmProcess.launchCeiling) helpers outside the \
            tools' groups still held their pipes, answered \(result.status) \
            \(result.output.debugDescription): the slots stayed taken for something \
            Helm cannot reach
            """)
        XCTAssertEqual(result.output, "hi")
    }

    /// The same, for a tool that ignores TERM: it is taken down by the KILL
    /// after the grace, and the run waits `settleAfterKill` for the reap before
    /// it looks at the group. Without that wait the reap is read before the
    /// KILL, the tool seems alive, and the slot stays with the helper thread
    /// until the holder outside the group lets go of the pipe, 20 s later.
    func testAToolThatIgnoresTermAndAHolderOutsideItsGroupLeaveNoSlotTaken() throws {
        let dir = scratchDirectory("process-timeout-ignores-term")
        let hanging = ScratchTool.script("""
            trap '' TERM
            echo $$ > "$1/c$2"
            /usr/bin/perl -e 'use POSIX; POSIX::setsid(); open(F, ">", $ARGV[0]); print F "$$\\n"; close(F); exec "/bin/sleep", "20"' "$1/e$2" &
            wait
            """, named: "ignores-term-and-starts-a-helper", in: dir)
        let quick = ScratchTool.script("printf hi", named: "answers-at-once", in: dir)
        ScratchTool.removeAtTeardown(self, dir: dir)

        try fillTheCeilingWithTimedOutRuns(tool: hanging, in: dir)
        for n in 0..<HelmProcess.launchCeiling {
            let tool = try XCTUnwrap(ScratchTool.pid(dir.appendingPathComponent("c\(n)")),
                                     "run \(n) never recorded its own pid")
            XCTAssertFalse(ScratchTool.isRunning(tool),
                           "the tool of run \(n) (pid \(tool)) ignores TERM and was meant to be gone after the KILL")
        }

        let result = HelmProcess.run("/bin/sh", [quick], timeout: 1)
        XCTAssertEqual(result.status, 0, """
            one more run, asked for after \(HelmProcess.launchCeiling) tools that ignored TERM \
            were killed and left a holder outside their groups, answered \
            \(result.status) \(result.output.debugDescription): the slots stayed taken \
            after the KILL
            """)
        XCTAssertEqual(result.output, "hi")
    }

    // MARK: - A tool's bytes are not "nothing"

    /// A tool that wrote a byte no UTF-8 text holds and exited 0. Whatever a
    /// caller is told, it is not "status 0 and nothing": every parser reads that
    /// as a tool that had nothing to say.
    func testAToolThatWroteOneUndecodableByteIsNotReadAsSayingNothing() {
        let unbounded = HelmProcess.run("/bin/sh", ["-c", "printf '\\377'"])
        XCTAssertFalse(saidNothing(unbounded), """
            a tool wrote one byte and exited 0; run answered status \(unbounded.status) \
            with output \(unbounded.output.debugDescription), which a caller reads as \
            a tool that had nothing to say
            """)
        let bounded = HelmProcess.run("/bin/sh", ["-c", "printf '\\377'"], timeout: 5)
        XCTAssertFalse(saidNothing(bounded), """
            the same tool through the bounded run answered status \(bounded.status) \
            with output \(bounded.output.debugDescription), which a caller reads as \
            a tool that had nothing to say
            """)
    }

    /// One bad byte in the middle of an otherwise readable line: the readable
    /// words are either handed on, or the run says by a status that it could not
    /// read the output. The line does not vanish whole behind a status 0.
    func testOneBadByteInTheMiddleOfAReadableLineDoesNotTakeTheWholeLine() {
        let line = "printf 'alpha \\377 beta\\n'"
        for (name, result) in [("run", HelmProcess.run("/bin/sh", ["-c", line])),
                               ("bounded run", HelmProcess.run("/bin/sh", ["-c", line], timeout: 5))] {
            let kept = result.output.contains("alpha") && result.output.contains("beta")
            XCTAssertTrue(result.status != 0 || kept, """
                \(name): a line of readable words with one bad byte between them \
                answered status \(result.status) with output \
                \(result.output.debugDescription)
                """)
        }
    }

    private func saidNothing(_ result: HelmProcess.Result) -> Bool {
        result.status == 0 && result.output.isEmpty
    }

    // MARK: - A tool that closes its output and keeps running

    /// The tool closes its standard output and goes on running: the read ends
    /// at once, and the tool is still out. The bounded run's deadline covers the
    /// tool, not only the read, so the caller is back within the timeout, the
    /// grace and the settle after a KILL, with slack for a loaded machine.
    ///
    /// The script records its own pid and whether descriptor 1 was open before
    /// and after it closed it, so the row can tell a closed pipe from a pipe
    /// that was merely held. It then becomes a `sleep` of the same pid, which
    /// the row removes at teardown by that pid. The `sleep` is 20 s, so a run
    /// that waits for it is seen as a long wait and ends by itself.
    func testAToolThatClosesItsOutputAndKeepsRunningIsStillCutOff() throws {
        let dir = scratchDirectory("process-timeout-closed-output")
        let tool = ScratchTool.script("""
            echo $$ > "$1/tool"
            if [ -e /dev/fd/1 ]; then echo open > "$1/before"; else echo closed > "$1/before"; fi
            exec >&-
            if [ -e /dev/fd/1 ]; then echo open > "$1/after"; else echo closed > "$1/after"; fi
            exec /bin/sleep 20
            """, named: "closes-its-output-and-sleeps", in: dir)
        ScratchTool.removeAtTeardown(self, dir: dir)

        let started = Date()
        let result = HelmProcess.run("/bin/sh", [tool, dir.path], timeout: 1)
        let elapsed = Date().timeIntervalSince(started)

        let before = try? String(contentsOf: dir.appendingPathComponent("before"), encoding: .utf8)
        let after = try? String(contentsOf: dir.appendingPathComponent("after"), encoding: .utf8)
        XCTAssertEqual(before?.trimmingCharacters(in: .whitespacesAndNewlines), "open",
                       "the pipe was not the tool's standard output to begin with")
        XCTAssertEqual(after?.trimmingCharacters(in: .whitespacesAndNewlines), "closed",
                       "the tool was meant to have closed its standard output; nothing below means anything otherwise")
        let pid = try XCTUnwrap(ScratchTool.pid(dir.appendingPathComponent("tool")),
                                "the script never recorded its own pid")
        XCTAssertLessThan(elapsed, 5, """
            the tool closed its output and kept running (pid \(pid)); the deadline was \
            1 s, the grace 2 s, and run returned only after \(elapsed) s with status \
            \(result.status)
            """)
        XCTAssertEqual(result.status, HelmProcess.timedOutStatus,
                       "a tool that closed its output and was cut off answered with its own status")
        XCTAssertEqual(result.output, "",
                       "a tool that closed its output and was cut off still gave output")
    }

    /// `launchCeiling` bounded runs of `tool` (which is given the directory and
    /// the run's number, and writes `e<n>` with the pid of a helper that holds
    /// the pipe from outside the tool's group), every one timing out at one
    /// second, under a clock deadline of its own. The helpers are checked
    /// alive: the premise of the rows that use this.
    private func fillTheCeilingWithTimedOutRuns(tool: String, in dir: URL) throws {
        let ceiling = HelmProcess.launchCeiling
        let statuses = StatusList()
        let group = DispatchGroup()
        for n in 0..<ceiling {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                statuses.add(HelmProcess.run("/bin/sh", [tool, dir.path, String(n)], timeout: 1).status)
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success,
                       "the bounded runs never came back")
        XCTAssertEqual(statuses.values, Array(repeating: HelmProcess.timedOutStatus, count: ceiling),
                       "every one of the \(ceiling) runs was meant to time out")
        for n in 0..<ceiling {
            let helper = try XCTUnwrap(ScratchTool.pid(dir.appendingPathComponent("e\(n)")),
                                       "run \(n) never recorded its helper")
            XCTAssertTrue(ScratchTool.isRunning(helper),
                          "the helper of run \(n) (pid \(helper)) was gone; nothing here holds its pipe")
        }
    }
}

/// A scratch shell script, the pids it writes down, and the means to remove
/// what a row started: only by those pids, and only while the process under
/// one is still a `sleep`.
enum ScratchTool {
    static func script(_ body: String, named name: String, in dir: URL) -> String {
        let url = dir.appendingPathComponent(name)
        try? Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        chmod(url.path, 0o755)
        return url.path
    }

    static func pid(_ file: URL) -> pid_t? {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let value = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value > 1 else { return nil }
        return value
    }

    /// Running, and not merely a zombie waiting to be reaped.
    static func isRunning(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_status != 5   // SZOMB
    }

    /// Gone within `seconds` of the wall clock.
    static func becomesGone(_ pid: pid_t, within seconds: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if !isRunning(pid) { return true }
            usleep(50_000)
        }
        return !isRunning(pid)
    }

    static func waitForFile(_ file: URL, within seconds: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if pid(file) != nil { return true }
            usleep(20_000)
        }
        return pid(file) != nil
    }

    /// Registered after the scratch directory's own teardown, so it runs first
    /// and the pid files are still there to read.
    static func removeAtTeardown(_ test: XCTestCase, dir: URL) {
        test.addTeardownBlock {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names {
                guard let target = pid(dir.appendingPathComponent(name)),
                      isRunning(target) else { continue }
                var comm = [CChar](repeating: 0, count: 64)
                proc_name(target, &comm, UInt32(comm.count))
                if String(cString: comm) == "sleep" { kill(target, SIGKILL) }
            }
        }
    }
}

final class StatusList: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Int32] = []
    func add(_ status: Int32) { lock.lock(); list.append(status); lock.unlock() }
    var values: [Int32] { lock.lock(); defer { lock.unlock() }; return list }
}
