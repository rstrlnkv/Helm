import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_KeepAwake_Engine

/// The grant carries its own withdrawal, and that is what makes every other
/// removal in this module affordable.
///
/// `sudoers` has no expiry and no conditionals, so a rule installed once stays
/// until something takes it out — and the only thing that could was an
/// administrator dialog, which costs a password and therefore could only be
/// asked for with somebody at the screen. Dragging `Helm.app` to the Trash runs
/// no code at all, so the grant outlived the application that asked for it,
/// naming an app that no longer exists.
///
/// The second line permits exactly one command: deleting this very file. It is
/// not a widening — the worst anything can do with it is take a privilege
/// away — and with it the withdrawal is `sudo -n`, silent and free, which is
/// the only kind a quitting process can actually carry out.
///
/// Two rejected shapes, so nobody re-derives them: pointing the rule at a
/// script inside the bundle would make deleting the app remove the grant, and
/// `/Applications` is writable by an admin without a password, so replacing
/// that script buys permanent passwordless root — a leak turned into an
/// escalation. A root-owned helper outside the bundle is not removed by
/// dragging the app to the Trash either.
final class TheRuleTakesItselfBackOutTests: XCTestCase {

    private let user = "someone"

    /// The command specs the file grants, one per rule line, with the
    /// `<user> ALL=(root) NOPASSWD:` preamble taken off.
    private func grantedCommands() -> [String] {
        SudoersRule.text(user: user)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
            .flatMap { line -> [String] in
                guard let colon = line.range(of: "NOPASSWD: ") else {
                    XCTFail("a rule line without a NOPASSWD command spec: \(line)")
                    return []
                }
                return line[colon.upperBound...]
                    .components(separatedBy: ", ")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
    }

    // MARK: - What the file permits

    func testTheFilePermitsItsOwnRemoval() {
        XCTAssertTrue(grantedCommands().contains("/bin/rm -f /etc/sudoers.d/helm-keepawake"),
                      "nothing in the grant can withdraw it, so only a password can — and "
                      + "dragging the app to the Trash never asks for one")
    }

    func testTheWithdrawalIsTheOnlyThingAddedToTheTwoPmsetCommands() {
        XCTAssertEqual(grantedCommands(), [
            "/usr/bin/pmset disablesleep 1",
            "/usr/bin/pmset disablesleep 0",
            "/bin/rm -f /etc/sudoers.d/helm-keepawake",
        ])
    }

    /// Argument-exact, one literal path. `pmset -a disablesleep 1` is refused
    /// for the same reason, and has been all along.
    func testNoGrantedCommandCanBeAimedAtAnythingElse() {
        for command in grantedCommands() {
            XCTAssertFalse(command.contains("*"), "a wildcard in \(command)")
            XCTAssertFalse(command.contains("ALL"), "a widening in \(command)")
            let words = command.split(separator: " ").map(String.init)
            XCTAssertTrue(words.first?.hasPrefix("/") == true,
                          "\(command) does not name an absolute program")
            for path in words.dropFirst() where path.hasPrefix("/") {
                XCTAssertEqual(path, SudoersRule.installedPath,
                               "\(command) names a path other than the rule's own file")
            }
        }
    }

    /// The words `sudo` is handed and the words the rule spells are one
    /// constant. Two spellings of the same command across the logic/port
    /// boundary is a name only one side ever changes, and `sudo` matches
    /// argument for argument: a drift is not an error anywhere, it is a
    /// withdrawal that silently starts asking for a password again.
    func testTheCallAndTheGrantAreOneSpelling() {
        XCTAssertTrue(grantedCommands().contains(SudoersRule.removeArguments.joined(separator: " ")))
        XCTAssertTrue(grantedCommands().contains(
            SudoersRule.disableSleepArguments(on: true).joined(separator: " ")))
        XCTAssertTrue(grantedCommands().contains(
            SudoersRule.disableSleepArguments(on: false).joined(separator: " ")))
    }

    // MARK: - The header

    /// `#` opens a comment in sudoers **except** for `#include` and
    /// `#includedir`, which pull in another file — so a header whose first word
    /// happened to be one of those would not be a header, it would be a
    /// directive. `@include` is the newer spelling of the same thing.
    func testEveryHeaderLineIsACommentAndNoneIsAnInclude() {
        let header = SudoersRule.text(user: user)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .prefix { $0.hasPrefix("#") }
        XCTAssertFalse(header.isEmpty, "a file found years from now with no header explains nothing")
        for line in header {
            let firstWord = line.dropFirst().split(separator: " ").first.map(String.init) ?? ""
            XCTAssertFalse(["include", "includedir"].contains(firstWord.lowercased()),
                           "\(line) is a directive, not a comment")
            XCTAssertFalse(line.hasPrefix("@"), "\(line) is a directive, not a comment")
        }
    }

    func testTheHeaderSaysHowToRemoveItByHand() {
        XCTAssertTrue(SudoersRule.text(user: user).contains("sudo rm \(SudoersRule.installedPath)"))
    }

    /// The file is what root writes, and a name outside ASCII in it is a
    /// question about `printf`, the shell's locale and `visudo` all at once.
    func testTheFileIsPlainASCII() {
        XCTAssertTrue(SudoersRule.text(user: user).allSatisfy { $0.isASCII })
    }

    // MARK: - The check that is not decorative

    /// `visudo -cf` on a scratch copy — never on `/etc/sudoers.d`, which this
    /// suite must not touch. It is the same check `installCommand` runs before
    /// the rule is moved into place.
    func testTheFileParses() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/usr/sbin/visudo"))
        let file = scratchDirectory("keepawake-sudoers").appendingPathComponent("rule")
        try SudoersRule.text(user: user).write(to: file, atomically: true, encoding: .utf8)
        let result = HelmProcess.run("/usr/sbin/visudo", ["-cf", file.path], timeout: 20)
        XCTAssertEqual(result.status, 0, result.output)
    }

    /// …and the same call on a file that is wrong says so, or the test above is
    /// a check that cannot fail.
    func testTheSameCheckRejectsAMalformedFile() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/usr/sbin/visudo"))
        let file = scratchDirectory("keepawake-sudoers-bad").appendingPathComponent("rule")
        try "someone ALL=(root NOPASSWD /usr/bin/pmset\n"
            .write(to: file, atomically: true, encoding: .utf8)
        let result = HelmProcess.run("/usr/sbin/visudo", ["-cf", file.path], timeout: 20)
        XCTAssertNotEqual(result.status, 0, "visudo accepted a file with a syntax error")
    }

    // MARK: - What travels to root

    /// The command root is given really does produce the file, run end to end
    /// with `/etc/sudoers.d` swapped for a scratch directory.
    ///
    /// Never against the real path — this suite must not touch it — and the swap
    /// is the whole of the difference: the same `printf`, the same quoting, the
    /// same `chmod`, the same `visudo -cf`, the same `mv`. It is the half
    /// `testTheFileParses` cannot see, because that one writes the text with
    /// Foundation and asks only whether the *text* parses. What broke here was
    /// the file becoming several lines: one `printf` argument with newlines in
    /// it cannot survive the AppleScript literal the command travels inside, so
    /// the lines are separate arguments, and that is a claim about a shell.
    func testTheInstallCommandReallyWritesTheFile() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/usr/sbin/visudo"))
        let directory = scratchDirectory("keepawake-install")
        let target = directory.appendingPathComponent("helm-keepawake").path
        let command = SudoersRule.installCommand(user: user)
            .replacingOccurrences(of: SudoersRule.installedPath, with: target)

        let result = HelmProcess.run("/bin/sh", ["-c", command], timeout: 30)

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(try String(contentsOfFile: target, encoding: .utf8),
                       SudoersRule.text(user: user).replacingOccurrences(
                           of: SudoersRule.installedPath, with: target) + "\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target + ".new"),
                       "the staging file was left behind")
    }

    /// The install writes the lines as separate `printf` arguments, because the
    /// whole command is one AppleScript double-quoted literal and a raw newline
    /// inside one is a syntax error rather than a newline.
    func testTheInstallCommandCarriesEveryLineOfTheFile() {
        let command = SudoersRule.installCommand(user: user)
        for line in SudoersRule.text(user: user).split(separator: "\n").map(String.init) {
            XCTAssertTrue(command.contains(line), "the install never writes: \(line)")
        }
        XCTAssertFalse(command.contains("\n"), "a newline cannot survive the AppleScript literal")
    }
}
