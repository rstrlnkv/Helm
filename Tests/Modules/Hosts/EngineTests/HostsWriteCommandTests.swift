import XCTest
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
}
