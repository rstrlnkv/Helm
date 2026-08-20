import Foundation
import XCTest
@testable import Module_Hosts_Engine

/// **What the terminal is answered with, and what it is not.**
///
/// `PTYProcess` answers every read that carries the word «passphrase», which is
/// the right rule for a tool whose wording changes between releases. The other
/// half of that rule is the one nothing tested: `ssh-keygen` has a second
/// question, and it is a destructive one —
///
/// ```
/// /Users/someone/.ssh/id_ed25519 already exists.
/// Overwrite (y/n)?
/// ```
///
/// An answer meant for a passphrase landing there is a key destroyed: whatever
/// the person typed begins with something, and `ssh-keygen` reads a leading `y`
/// as yes. The engine's `nameTaken` refusal is the first defence and it is a
/// reading taken before the child exists — a key can arrive in the directory
/// between the check and the spawn, from a shell in another window or a second
/// Helm. So the pty itself must not answer that question, and this is where
/// that is checked.
///
/// Every child here is `/bin/sh`. Nothing reads anybody's `~/.ssh`, nothing
/// touches an agent, and nothing is written anywhere.
final class TheAnswerGoesOnlyToTheQuestionAskedTests: XCTestCase {

    private let secret = "hunter2"

    /// The overwrite question, asked exactly as `ssh-keygen` asks it, with a
    /// read that gives up rather than hanging — so the answer is «nothing was
    /// typed», said by the child, rather than a deadline this test would have
    /// to read as evidence of absence.
    func testTheOverwriteQuestionIsNeverAnswered() {
        var passphrase = Data(secret.utf8)
        let result = PTYProcess.run(
            "/bin/sh",
            ["-c", """
                printf '/Users/someone/.ssh/id_ed25519 already exists.\\nOverwrite (y/n)? '
                if read -t 3 -r reply; then printf '\\nanswered:%s\\n' "$reply"
                else printf '\\nunanswered\\n'; fi
                """],
            answering: &passphrase, timeout: 15)

        XCTAssertEqual(result.status, 0, "precondition: the child ran to the end: \(result.output)")
        XCTAssertTrue(result.output.contains("Overwrite (y/n)?"),
                      "precondition: the question was asked at all: \(result.output)")
        XCTAssertTrue(result.output.contains("unanswered"), """
            «Overwrite (y/n)?» was answered by the pty. Whatever the person typed as a \
            passphrase went to the question about replacing a key that already exists, and \
            `ssh-keygen` reads any word beginning with `y` as yes — which is the one way this \
            module can destroy a key. The transcript: \(result.output)
            """)
        XCTAssertFalse(result.output.contains(secret),
                       "the passphrase reached a child that never asked for one: \(result.output)")
    }

    /// The rule the file states, kept: a question is matched on the word,
    /// whatever case the tool spells it in. `ssh-add` has said «Enter
    /// passphrase», «Enter PEM pass phrase» and «Bad passphrase» across
    /// releases, and only the first two are questions — so the word is matched
    /// case-blind and this is the half that must keep working.
    func testAPromptShoutingTheWordIsStillAnswered() {
        var passphrase = Data(secret.utf8)
        let result = PTYProcess.run(
            "/bin/sh",
            ["-c", "printf 'Enter PASSPHRASE for key: '; read -r x; echo got:$x"],
            answering: &passphrase, timeout: 15)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("got:\(secret)"),
                      "a prompt spelled in capitals went unanswered: \(result.output)")
    }

    /// A child that asks nothing gets nothing — and the buffer is still zeroed,
    /// which is the path where a leftover secret would sit longest: no prompt,
    /// no write, and a caller that believes the port emptied its buffer.
    func testAChildThatAsksNothingIsToldNothing() {
        var passphrase = Data(secret.utf8)
        let result = PTYProcess.run("/bin/sh", ["-c", "echo quiet"],
                                    answering: &passphrase, timeout: 15)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "quiet")
        XCTAssertTrue(passphrase.isEmpty, "the caller's buffer kept the secret")
    }
}
