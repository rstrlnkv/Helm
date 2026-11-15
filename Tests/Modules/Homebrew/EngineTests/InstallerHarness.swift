import Foundation
import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

// The harness the installer-wrapper tests share: take the command `installBrew`
// composes from the engine itself, point it at a local file, run it for real.

/// What one launched child said and how it ended.
final class Run: @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var _status: Int32?
    private var _exits = 0
    private var _lines: [String] = []
    var status: Int32? { lock.lock(); defer { lock.unlock() }; return _status }
    var exits: Int { lock.lock(); defer { lock.unlock() }; return _exits }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
    func line(_ l: String) { lock.lock(); _lines.append(l); lock.unlock() }
    func exit(_ s: Int32) { lock.lock(); _status = s; _exits += 1; lock.unlock(); done.signal() }
}

extension XCTestCase {

    /// The string the engine would have handed to `/bin/bash -c`.
    func composedInstaller() throws -> String {
        let rig = WaitRig()
        rig.tools.gitExecutable = true
        rig.engine.installBrew()
        let args = try XCTUnwrap(rig.runner.calls.first, "the engine launched nothing")
        XCTAssertEqual(args.first, "-c", "the installer stopped being a `bash -c` string")
        return try XCTUnwrap(args.last)
    }

    /// The engine's own string with the two fixtures in it. The URL is found by
    /// its scheme rather than written out again, so a moved installer changes
    /// nothing here.
    func rehosted(_ command: String, source: URL, temporaries: URL) throws -> String {
        let url = try XCTUnwrap(command.split(separator: " ").first { $0.hasPrefix("https://") },
                                "the command downloads nothing over https any more")
        return command
            .replacingOccurrences(of: String(url), with: "file://\(source.path)")
            .replacingOccurrences(of: "/usr/bin/mktemp",
                                  with: "/usr/bin/mktemp -p \(temporaries.path) -t helm")
    }

    func start(_ command: String, trace: Bool = false, reach: StopReach = .wholeGroup) -> (RunningProcess, Run) {
        let run = Run()
        let handle = ShellProcessRunner().stream("/bin/bash", [trace ? "-xc" : "-c", command], env: [:], reach: reach,
                                                 onLine: { run.line($0) }, onExit: { run.exit($0) })
        return (handle, run)
    }

    /// Waits on the wall clock for `condition`; a condition polled is the only
    /// honest wait for a process this test does not own the end of.
    func eventually(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
    }
}
