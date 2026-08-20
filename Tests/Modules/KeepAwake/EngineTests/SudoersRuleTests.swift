import HelmRuntime
import XCTest
@testable import Module_KeepAwake_Engine

/// What root is asked to do, pinned by shape rather than by outcome.
///
/// The install used to stage the rule in `$TMPDIR` and hand root the *path*:
/// the staged path stood in `ps auxww` for as long as the password prompt was
/// up, `visudo -cf` checks syntax and not authorship, and `install` copies
/// whatever is at the path when it runs. Swapping the file for
/// `<user> ALL=(ALL) NOPASSWD: ALL` passed the check and bought permanent
/// passwordless root. These tests say the content travels, never a path the
/// user can write.
final class SudoersRuleTests: XCTestCase {

    private let user = "someone"

    // MARK: - The rule

    /// The whole file, character for character. The rule lines are argued
    /// separately in `TheRuleTakesItselfBackOutTests`, which reads them as
    /// command specs rather than as text; this is the one place that says what
    /// lands on disk.
    func test_the_file_is_a_header_and_three_granted_commands() {
        XCTAssertEqual(SudoersRule.text(user: user), """
            # Installed by Helm - Keep Awake, closed-lid option.
            # Lets this user run exactly the two pmset commands below without a password,
            # and lets Helm withdraw this file again without one.
            # Remove it by hand with:  sudo rm /etc/sudoers.d/helm-keepawake
            someone ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0
            someone ALL=(root) NOPASSWD: /bin/rm -f /etc/sudoers.d/helm-keepawake
            """)
    }

    // MARK: - The privileged command

    func test_install_command_names_no_user_writable_path() {
        let command = SudoersRule.installCommand(user: user)
        // An empty command satisfies every "does not contain" below, so say
        // first that there is a command at all.
        XCTAssertTrue(command.contains(SudoersRule.installedPath + ".new"))
        let temporaryDirectory = FileManager.default.temporaryDirectory.path
        XCTAssertFalse(command.contains(temporaryDirectory))
        XCTAssertFalse(command.contains("TMPDIR"))
        XCTAssertFalse(command.contains("/var/folders"))
        XCTAssertFalse(command.contains(NSHomeDirectory()))
        // Every file the command touches is in root-owned /etc/sudoers.d.
        for token in command.split(separator: " ").map(String.init)
        where token.hasPrefix("/") && !token.hasPrefix("/usr/bin/") && !token.hasPrefix("/bin/")
                && !token.hasPrefix("/usr/sbin/") {
            XCTAssertTrue(token.hasPrefix("/etc/sudoers.d/"), "unexpected path \(token)")
        }
    }

    func test_install_command_carries_the_rule_text_itself() {
        let command = SudoersRule.installCommand(user: user)
        for line in SudoersRule.lines(user: user) {
            XCTAssertTrue(command.contains(line), "the install never writes: \(line)")
        }
    }

    func test_install_command_writes_then_checks_then_moves_into_place() {
        let command = SudoersRule.installCommand(user: user)
        let staging = SudoersRule.installedPath + ".new"
        guard let write = command.range(of: "/usr/bin/printf"),
              let mode = command.range(of: "/bin/chmod 440 \(staging)"),
              let check = command.range(of: "/usr/sbin/visudo -cf \(staging)"),
              let move = command.range(of: "/bin/mv \(staging) \(SudoersRule.installedPath)")
        else { return XCTFail("missing a step in \(command)") }
        XCTAssertTrue(write.lowerBound < mode.lowerBound)
        XCTAssertTrue(mode.lowerBound < check.lowerBound)
        XCTAssertTrue(check.lowerBound < move.lowerBound)
        // The rule reaches the filesystem only under the .new name, so a
        // half-written or unchecked file is never what sudo reads.
        XCTAssertTrue(command.contains("> \(staging)"))
    }

    func test_install_command_reports_failure_and_leaves_nothing_behind() {
        let command = SudoersRule.installCommand(user: user)
        let staging = SudoersRule.installedPath + ".new"
        XCTAssertTrue(command.contains("|| { /bin/rm -f \(staging); exit 1; }"))
    }

    func test_remove_command_deletes_only_the_installed_rule() {
        XCTAssertEqual(SudoersRule.removeCommand(), "/bin/rm -f \(SudoersRule.installedPath)")
    }

    // MARK: - Quoting

    func test_a_quote_in_the_account_name_cannot_end_the_shell_quoting() {
        let command = SudoersRule.installCommand(user: "me' ALL=(ALL) NOPASSWD: ALL #")
        XCTAssertTrue(command.contains("'\\''"))
        XCTAssertFalse(command.contains("me' ALL=(ALL) NOPASSWD: ALL #"))
    }

    /// The escaping lives in `AppleScript` (HelmRuntime) now — it was here and
    /// in Homebrew's privileged runner, two copies of the one thing standing
    /// between a command root runs and a command somebody appends to.
    func test_apple_script_literal_escapes_backslash_and_quote() {
        XCTAssertEqual(AppleScript.literal(#"a\b"c"#), #"a\\b\"c"#)
    }

    func test_privileged_script_is_one_escaped_literal_and_asks_for_admin() {
        let command = SudoersRule.installCommand(user: user)
        let script = SudoersRule.installScript(user: user)
        XCTAssertEqual(script, "do shell script \"\(AppleScript.literal(command))\" "
                             + "with administrator privileges")
        // Nothing between the literal's own quotes may close it early: the only
        // unescaped double quotes in the script are the two that delimit it.
        var unescaped = 0
        var afterBackslash = false
        for character in script {
            if afterBackslash { afterBackslash = false; continue }
            if character == "\\" { afterBackslash = true; continue }
            if character == "\"" { unescaped += 1 }
        }
        XCTAssertEqual(unescaped, 2)
    }
}
