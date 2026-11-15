import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_KeepAwake_Engine

/// Which command each half of `PmsetClamshellPort` sends to root, and how it
/// reads the answer. The route to the administrator dialog was reachable by no
/// test: swapping install for remove, or reading «not done» as success, stayed
/// green. A cancelled dialog reported as a removal is a grant believed gone
/// that is still there.
final class PmsetClamshellPortPrivilegedTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String] = []
        func add(_ command: String) { lock.lock(); seen.append(command); lock.unlock() }
        var commands: [String] { lock.lock(); defer { lock.unlock() }; return seen }
    }

    private func present() throws -> String {
        let path = scratchDirectory("sudoers").appendingPathComponent("rule").path
        XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: Data()))
        return path
    }

    private func install(_ outcome: PrivilegedOutcome) -> (Bool, [String]) {
        let recorder = Recorder()
        let port = PmsetClamshellPort(sudoersPath: "/nonexistent/helm") { recorder.add($0); return outcome }
        let done = expectation(description: "install")
        nonisolated(unsafe) var result = false
        port.installSudoers { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return (result, recorder.commands)
    }

    private func remove(_ outcome: PrivilegedOutcome) throws -> (Bool, [String]) {
        let recorder = Recorder()
        let port = PmsetClamshellPort(sudoersPath: try present()) { recorder.add($0); return outcome }
        let done = expectation(description: "remove")
        nonisolated(unsafe) var result = false
        port.removeSudoers { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return (result, recorder.commands)
    }

    func test_install_sends_the_install_command_and_reads_each_outcome() {
        let user = NSUserName()
        for (outcome, expected) in [(PrivilegedOutcome.done, true), (.declined, false), (.failed(1), false)] {
            let (result, commands) = install(outcome)
            XCTAssertEqual(commands, [SudoersRule.installCommand(user: user)])
            XCTAssertEqual(result, expected, "\(outcome)")
        }
    }

    func test_remove_sends_the_remove_command_and_reads_each_outcome() throws {
        for (outcome, expected) in [(PrivilegedOutcome.done, true), (.declined, false), (.failed(1), false)] {
            let (result, commands) = try remove(outcome)
            XCTAssertEqual(commands, [SudoersRule.removeCommand()])
            XCTAssertEqual(result, expected, "\(outcome)")
        }
    }

    func test_remove_with_no_rule_present_asks_for_nothing() {
        let recorder = Recorder()
        let port = PmsetClamshellPort(sudoersPath: "/nonexistent/helm") { recorder.add($0); return .failed(1) }
        let done = expectation(description: "remove")
        nonisolated(unsafe) var result = false
        port.removeSudoers { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertTrue(result)
        XCTAssertEqual(recorder.commands, [])
    }
}

/// `pmset -g` that did not succeed has no report: its output is whatever the
/// failing tool printed, and reading that as the lid state is a guess.
final class PmsetReportIsNilWhenPmsetFailsTests: XCTestCase {

    func test_a_failed_pmset_has_no_report_and_a_good_one_is_passed_through() {
        let failed = PmsetClamshellPort(pmset: { HelmProcess.Result(status: 1, output: "not a report") })
        XCTAssertNil(failed.pmsetReport())
        let good = PmsetClamshellPort(pmset: { HelmProcess.Result(status: 0, output: "SleepDisabled 1") })
        XCTAssertEqual(good.pmsetReport(), "SleepDisabled 1")
    }
}

/// Stopping takes the tokens back out and forgets them, so a second stop (the
/// `deinit` one) has nothing left to remove.
final class WorkspaceAppPortForgetsItsTokensTests: XCTestCase {

    func test_stop_clears_the_observers_start_registered() {
        let port = WorkspaceAppPort()
        port.startObserving {}
        XCTAssertEqual(port.tokens.count, 2)
        port.stopObserving()
        XCTAssertEqual(port.tokens.count, 0)
    }
}
