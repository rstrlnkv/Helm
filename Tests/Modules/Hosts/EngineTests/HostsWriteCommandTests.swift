import XCTest
import HelmRuntime
@testable import Module_Hosts_Engine

/// What root is asked to do, and what may reach the sentence that asks.
final class HostsWriteCommandTests: XCTestCase {

    func testTheCommandCarriesTheContentAndNeverAPath() throws {
        let command = try XCTUnwrap(HostsWrite.command(base64: "MTI3LjAuMC4xCg=="))
        XCTAssertTrue(command.contains("MTI3LjAuMC4xCg=="))
        XCTAssertTrue(command.contains("/etc/hosts"))
        XCTAssertFalse(command.contains(NSTemporaryDirectory()),
                       "a staged file is a file another process can swap under root")
    }

    func testTheDNSCacheIsFlushedInTheSamePrivilegedCommand() throws {
        let command = try XCTUnwrap(HostsWrite.command(base64: "QQ=="))
        XCTAssertTrue(command.contains("dscacheutil"))
        XCTAssertTrue(command.contains("mDNSResponder"))
    }

    /// The alphabet is the gate. None of these can end an AppleScript literal
    /// or a shell word, because none of them may enter at all.
    func testAnythingOutsideTheBase64AlphabetIsRefused() {
        for hostile in ["QQ==\"; rm -rf /", "QQ== $(whoami)", "QQ==`id`",
                        "QQ==\\", "QQ==;id", "QQ== > /etc/sudoers", "QQ==\n/bin/sh",
                        "QQ=='", "QQ==|id", "", "not base64!"] {
            XCTAssertNil(HostsWrite.command(base64: hostile),
                         "\(hostile.debugDescription) reached the command")
        }
    }

    func testAnOrdinaryPayloadIsAccepted() {
        XCTAssertNotNil(HostsWrite.command(base64: "abcXYZ0189+/=="))
    }

    /// A round trip through the encoder the engine actually uses, so the two
    /// halves cannot drift: whatever `encode` produces, `command` must accept.
    func testEverythingTheEncoderProducesIsAccepted() {
        let awkward = "127.0.0.1\tlocalhost # \"quote\" $VAR `id` \\ ; | & \n::1 ünïcødé\n"
        let encoded = HostsWrite.encode(awkward)
        XCTAssertNotNil(HostsWrite.command(base64: encoded))
        XCTAssertEqual(Data(base64Encoded: encoded).flatMap { String(bytes: $0, encoding: .utf8) },
                       awkward)
    }

    // MARK: - The count guard
    //
    // Everything below is about the *order* of the sentence rather than its
    // words, and it is here because `|| exit 1` reads like a promise the file
    // survived and is not one. Measured on macOS 27, 2026-08-18, against
    // scratch files — never `/etc/hosts`, and never through `osascript`.

    /// The number the command tells the shell to expect, read back out of the
    /// sentence — so these tests read what root would read, not what Swift
    /// meant to say.
    private func expectedCount(in command: String) -> Int? {
        guard let eq = command.range(of: "-eq ") else { return nil }
        return Int(command[eq.upperBound...].prefix { $0 == "-" || $0.isNumber })
    }

    /// **The redirect must not exist until the payload has proved itself.**
    /// `>` truncates before the pipeline runs, so a check that happens after it
    /// is a post-mortem: a 20-byte scratch file went to 0 bytes and *then* the
    /// decoder reported the failure.
    func testTheCountGuardStandsBeforeTheRedirect() throws {
        let command = try XCTUnwrap(HostsWrite.command(base64: HostsWrite.encode("127.0.0.1\n")))
        let guardAt = try XCTUnwrap(command.range(of: "-eq "), "no count guard in the command at all")
        let redirectAt = try XCTUnwrap(command.range(of: "> \(HostsWrite.path)"))
        XCTAssertTrue(guardAt.lowerBound < redirectAt.lowerBound,
                      "a count checked after the truncation is a post-mortem")
    }

    /// The guard's number is the byte count of the file itself, so the sentence
    /// and the payload cannot drift apart.
    func testTheGuardCountsTheBytesTheEncoderWasGiven() throws {
        let awkward = "127.0.0.1\tlocalhost # \"quote\" $VAR `id` \\ ; | & \n::1 ünïcødé\n"
        let command = try XCTUnwrap(HostsWrite.command(base64: HostsWrite.encode(awkward)))
        let count = try XCTUnwrap(expectedCount(in: command), "no count guard in the command at all")
        XCTAssertEqual(count, Data(awkward.utf8).count)
    }

    /// Five payloads inside the alphabet that `/usr/bin/base64 -D` answers with
    /// **nothing**: `QQ=`, `Q`, `=` and `====` at status 0, and `UP9PJMT=` with
    /// an error — every one of them measured at 0 bytes. Each still produces a
    /// command, because the alphabet is the only refusal; none may reach the
    /// redirect, so the guard's number must be one `wc -c` cannot answer with.
    func testAPayloadThatDecodesToNothingCannotReachTheRedirect() throws {
        for hollow in ["QQ=", "Q", "=", "====", "UP9PJMT="] {
            let command = try XCTUnwrap(HostsWrite.command(base64: hollow), hollow)
            let count = try XCTUnwrap(expectedCount(in: command), "no count guard for \(hollow)")
            XCTAssertNotEqual(count, 0, "\(hollow) would meet its own guard and empty the file")
        }
    }

    /// The other half of the same question: the guard must not refuse a payload
    /// that is fine. `/bin/echo abcXYZ0189+/== | /usr/bin/base64 -D` gives 9
    /// bytes, so 9 is what the sentence has to ask for.
    func testTheOrdinaryPayloadMeetsItsOwnGuard() throws {
        let command = try XCTUnwrap(HostsWrite.command(base64: "abcXYZ0189+/=="))
        XCTAssertEqual(expectedCount(in: command), 9)
    }

    // MARK: - The ceiling

    /// The kernel's own answer, asked here rather than copied from the source
    /// under test — the two sides of this check must not be one constant.
    private var argMax: Int { Int(sysconf(_SC_ARG_MAX)) }

    /// The largest file `fits` accepts, found by bisection rather than by
    /// re-deriving the formula the subject uses.
    private func largestFittingSize() -> Int {
        var low = 0, high = 4 * argMax
        XCTAssertTrue(HostsWrite.fits(text(of: low)))
        XCTAssertFalse(HostsWrite.fits(text(of: high)))
        while high - low > 1 {
            let middle = (low + high) / 2
            if HostsWrite.fits(text(of: middle)) { low = middle } else { high = middle }
        }
        return low
    }

    private func text(of bytes: Int) -> String { String(repeating: "a", count: bytes) }

    func testAnOrdinaryHostsFileFits() {
        XCTAssertTrue(HostsWrite.fits("127.0.0.1\tlocalhost\n::1\tlocalhost\n"))
        XCTAssertTrue(HostsWrite.fits(""), "an empty file is not a large one")
    }

    /// Ad-blocking hosts files run 1–4 MB. They cannot be written at all, and
    /// this is where that is said rather than discovered at the exec.
    func testAnAdBlockingHostsFileDoesNotFit() {
        XCTAssertFalse(HostsWrite.fits(String(repeating: "0.0.0.0\tads.example.com\n",
                                              count: 50_000)))
    }

    /// **The promise, measured against the real sentence.** Whatever `fits`
    /// accepts, `/bin/sh -c` must be able to carry — so the AppleScript this
    /// module actually builds for the largest accepted file is weighed against
    /// the kernel's `ARG_MAX`. An arithmetic that spelled the payload once
    /// instead of twice fails here and nowhere else.
    func testWhatFitsIsSomethingTheExecCanCarry() throws {
        let biggest = text(of: largestFittingSize())
        let shell = try XCTUnwrap(HostsWrite.command(base64: HostsWrite.encode(biggest)))
        let script = AppleScript.administratorShellScript(shell)
        XCTAssertLessThanOrEqual(script.utf8.count, argMax,
                                 "a file this module says it can write cannot be exec'd")
    }

    /// The other side, without which a `fits` that always answered false would
    /// pass the one above. The ceiling is ≈390 KB because the count guard
    /// spells the payload twice; it must not have quietly become 4 KB.
    func testTheCeilingIsNotFarBelowWhatTheExecAllows() throws {
        let biggest = text(of: largestFittingSize())
        let shell = try XCTUnwrap(HostsWrite.command(base64: HostsWrite.encode(biggest)))
        let script = AppleScript.administratorShellScript(shell)
        XCTAssertGreaterThan(script.utf8.count, argMax * 9 / 10,
                             "the ceiling gives away more of ARG_MAX than the environment needs")
    }

    /// A refusal from the ceiling and a refusal from the alphabet must not be
    /// the same answer: the engine reads them as `.tooLarge` and `.failed`, and
    /// somebody with a 2 MB file is told which one happened.
    func testTheCeilingIsAskedOfTheTextAndTheAlphabetOfThePayload() {
        let overSized = text(of: largestFittingSize() + 1)
        XCTAssertFalse(HostsWrite.fits(overSized))
        XCTAssertNotNil(HostsWrite.command(base64: HostsWrite.encode(overSized)),
                        "the gate refused it too, so the two refusals cannot be told apart")
    }
}
