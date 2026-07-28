import Foundation

/// The one way Helm runs a command-line tool.
///
/// There were five of these, and they disagreed on the two things that matter.
///
/// **Order.** Two of them called `waitUntilExit()` *before* reading the pipe. A
/// child whose output exceeds the pipe buffer blocks on the write while the
/// parent blocks on the wait, and neither ever finishes. The outputs happen to
/// be short today; the pattern was there to be copied.
///
/// **The wait itself.** `Process.waitUntilExit()` polls a run loop in 50 ms
/// steps, so every call paid about 67 ms whether or not the child had already
/// finished — measured at 70.6 ms for `/usr/bin/true` against 1.3 ms for a bare
/// spawn. `Leftovers` ran three tools per scan and spent two thirds of the scan
/// inside that poll. Reading to EOF already proves the child closed its output;
/// the termination handler supplies the status without the poll.
public enum HelmProcess {
    public struct Result: Sendable {
        public let status: Int32
        public let output: String
        public init(status: Int32, output: String) {
            self.status = status
            self.output = output
        }
    }

    @discardableResult
    public static func run(_ path: String,
                           _ arguments: [String],
                           env: [String: String]? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let env {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in env { merged[key] = value }
            process.environment = merged
        }

        let out = Pipe()
        process.standardOutput = out
        // Discarded, not merged: a tool's diagnostics are not its output, and
        // every caller here parses what it gets.
        //
        // `nullDevice`, not a `Pipe()`. A pipe nobody reads holds about 64 KB
        // and then blocks the child in `write(2)` — so it never exits, never
        // closes stdout, and the read below never returns. That is the same
        // deadlock this function reads-before-waiting to avoid on the stdout
        // side, reintroduced on the other one. A `brew` command with a
        // deprecation warning per formula reaches 64 KB easily, and the caller
        // is parked for the life of the process with an orphan child blocked
        // behind it. Discarding means sending it nowhere, not sending it
        // somewhere with no reader.
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do { try process.run() } catch { return Result(status: -1, output: "") }

        // Read first. This returns when the child closes stdout, which is what
        // makes the wait below immediate rather than a poll.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        finished.wait()
        return Result(status: process.terminationStatus,
                      output: String(data: data, encoding: .utf8) ?? "")
    }
}
