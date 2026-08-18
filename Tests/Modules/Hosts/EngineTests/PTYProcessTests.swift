import XCTest
@testable import Module_Hosts_Engine

/// The pty, against real children.
///
/// **Fakes are no use here.** What this type exists for is a property of the
/// operating system — that a passphrase written to a terminal is not in
/// `ps auxww` and an argument is — and a fake of `posix_spawn` would only
/// restate what the author already believed. Every child below is `/bin/sh`,
/// takes no network and touches no file of anybody's.
final class PTYProcessTests: XCTestCase {

    /// The child asks the way it asks a person, and gets an answer.
    func testAChildThatAsksForAPassphraseIsAnswered() {
        var secret = Data("hunter2".utf8)
        let result = PTYProcess.run("/bin/sh",
                                    ["-c", "printf 'Enter passphrase: '; read -r x; echo got:$x"],
                                    answering: &secret, timeout: 10)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("got:hunter2"),
                      "the child never received the answer: \(result.output)")
    }

    /// **The property this file exists for.** The child prints its own command
    /// line — what any process on this machine can read out of `ps auxww` — and
    /// the secret is not in it, because it was never an argument.
    ///
    /// **Only the `argv:` line is examined, and that is the point.** The first
    /// version of this check read the whole transcript, which also carries
    /// whatever the terminal echoed: it passed because echo is off, so it was
    /// standing on the guard next door rather than on its own subject. Two
    /// checks that can only fail together are one check.
    func testTheSecretIsNotInTheChildsCommandLine() {
        var secret = Data("hunter2".utf8)
        let result = PTYProcess.run(
            "/bin/sh",
            // The newline is deliberate: the prompt ends without one, so the
            // `ps` output would otherwise land on the prompt's own line and
            // the filter below would find no line beginning with the marker.
            ["-c", "printf 'Enter passphrase: '; read -r x; printf '\\n'; "
             + "ps -ww -o args= -p $$ | sed 's/^/argv:/'"],
            answering: &secret, timeout: 10)
        XCTAssertEqual(result.status, 0)
        let argv = result.output.split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("argv:") }
        XCTAssertFalse(argv.isEmpty, "precondition: no argv line in <\(result.output)>")
        XCTAssertFalse(argv.contains { $0.contains("hunter2") },
                       "the passphrase is in the child's own command line: \(argv)")
    }

    /// **The transcript does not carry the answer either**, which is a
    /// different question from the command line and was answered wrongly at
    /// first: a terminal echoes what is written to it, so the first draft of
    /// this file read back «Enter passphrase: hunter2» from a child that had
    /// done nothing wrong. The port clears echo before the child exists, so
    /// this holds whatever the tool's own habits are — `ssh-keygen` turns echo
    /// off while it asks and that is not a property this code may lean on.
    func testTheTranscriptDoesNotEchoTheAnswer() {
        var secret = Data("hunter2".utf8)
        let result = PTYProcess.run("/bin/sh",
                                    ["-c", "printf 'Enter passphrase: '; read -r x; echo done"],
                                    answering: &secret, timeout: 10)
        XCTAssertTrue(result.output.contains("done"), "precondition: the child ran")
        XCTAssertFalse(result.output.contains("hunter2"),
                       "the terminal echoed the passphrase into the transcript")
    }

    /// Zeroed on the way out, and the caller's buffer is the one zeroed — a
    /// secret this code merely stopped referring to is a secret still in the
    /// heap.
    func testTheSecretIsZeroedWhateverHappens() {
        var answered = Data("hunter2".utf8)
        _ = PTYProcess.run("/bin/sh", ["-c", "printf 'Enter passphrase: '; read -r x"],
                           answering: &answered, timeout: 10)
        XCTAssertTrue(answered.isEmpty)

        // The paths that never reach a prompt zero it too: a spawn that failed
        // is the one where a leftover secret would sit longest.
        var never = Data("hunter2".utf8)
        let missing = PTYProcess.run("/nonexistent/tool", [], answering: &never, timeout: 5)
        XCTAssertEqual(missing.status, PTYProcess.couldNotStartStatus)
        XCTAssertTrue(never.isEmpty)
    }

    /// It really is a terminal, **and the child has it as its controlling
    /// terminal** — which is the property `POSIX_SPAWN_SETSID` is set for.
    /// `readpassphrase` opens `/dev/tty`, and `/dev/tty` is the controlling
    /// terminal or nothing; without a session of its own the child would find
    /// Helm's, which in a bundled app is nothing at all, and fall back to
    /// whatever stdin happened to be.
    ///
    /// **The first version of this check measured `ps`'s keyword table.** It
    /// asked for `ps -o sid=`, which macOS's `ps` does not have — the child
    /// printed «keyword not found» and the comparison failed for a reason that
    /// had nothing to do with sessions. Writing to `/dev/tty` is the question
    /// itself: it succeeds only when there is a controlling terminal, and what
    /// it writes comes back through the pty, so the evidence is in the
    /// transcript.
    func testTheChildGetsATerminalAndItsOwnSession() {
        var none = Data()
        let result = PTYProcess.run(
            "/bin/sh",
            ["-c", "test -t 0 && echo isatty; "
             + "printf 'ctty-ok\\n' > /dev/tty 2>/dev/null || echo no-ctty"],
            answering: &none, timeout: 10)
        XCTAssertTrue(result.output.contains("isatty"), "stdin is not a terminal")
        XCTAssertTrue(result.output.contains("ctty-ok"),
                      "the child has no controlling terminal, so /dev/tty is not its pty: "
                      + result.output)
    }

    /// A child that sits there is killed at the deadline and says so — the
    /// status is not one a child can produce, so a timeout is never read as an
    /// ordinary failure.
    func testAChildThatNeverAnswersIsKilledAtTheDeadline() {
        var none = Data()
        let started = Date()
        let result = PTYProcess.run("/bin/sh", ["-c", "sleep 30"], answering: &none, timeout: 1)
        XCTAssertEqual(result.status, PTYProcess.timedOutStatus)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10,
                          "the deadline did not end it")
    }

    /// `ssh-keygen` asks twice — the passphrase, then the confirmation — and
    /// both get the same answer. Counting the prompts would break on the next
    /// wording change; matching the word is what survives one.
    func testEveryPromptThatAsksIsAnswered() {
        var secret = Data("hunter2".utf8)
        let result = PTYProcess.run(
            "/bin/sh",
            ["-c", """
                printf 'Enter passphrase (empty for no passphrase): '; read -r a
                printf 'Enter same passphrase again: '; read -r b
                test "$a" = "$b" && echo matched:$a
                """],
            answering: &secret, timeout: 10)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("matched:hunter2"),
                      "the second prompt went unanswered: \(result.output)")
    }
}
