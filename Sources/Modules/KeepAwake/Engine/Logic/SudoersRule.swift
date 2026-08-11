import Foundation
import HelmRuntime

/// The sudoers rule that lets Keep Awake run `pmset disablesleep`, and the
/// exact command root is asked to run to put it there.
///
/// Pure text, so the shape of what root does is a unit test rather than a
/// comment. It was a comment before, and the comment was wrong: the rule was
/// staged in `$TMPDIR` and only its *path* was handed to the privileged shell.
/// The path stands in `ps auxww` for as long as the password prompt is up —
/// seconds to minutes, not a race — `visudo -cf` checks syntax and not
/// authorship, and `install` copies whatever is at that path when it runs. Any
/// process running as this user could swap the file for
/// `<user> ALL=(ALL) NOPASSWD: ALL`, pass the check and be handed permanent
/// passwordless root. The content travels now; no user-writable path is named.
enum SudoersRule {
    /// Where sudo reads the rule from. `/etc/sudoers.d` is root-owned, so every
    /// file this command touches is one only root can write.
    static let installedPath = "/etc/sudoers.d/helm-keepawake"

    /// Written first under this name so sudo never reads a half-written or
    /// unchecked file: the move into place is a rename on the same filesystem.
    static let stagingPath = installedPath + ".new"

    static let pmsetPath = "/usr/bin/pmset"

    /// As narrow as it was: the two exact commands the module runs, nothing else.
    static func text(user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: \(pmsetPath) disablesleep 1, \(pmsetPath) disablesleep 0"
    }

    /// Write, lock down, check, move — and on any failure remove the staging
    /// file and report the failure. Without the `exit 1` a successful cleanup
    /// would be the command's exit status, and a refused rule would read as
    /// installed.
    static func installCommand(user: String) -> String {
        "/usr/bin/printf '%s\\n' \(shellQuoted(text(user: user))) > \(stagingPath)"
            + " && /bin/chmod 440 \(stagingPath)"
            + " && /usr/sbin/visudo -cf \(stagingPath)"
            + " && /bin/mv \(stagingPath) \(installedPath)"
            + " || { /bin/rm -f \(stagingPath); exit 1; }"
    }

    static func removeCommand() -> String { "/bin/rm -f \(installedPath)" }

    static func installScript(user: String) -> String {
        privilegedScript(installCommand(user: user))
    }

    static func removeScript() -> String { privilegedScript(removeCommand()) }

    // MARK: -

    /// `AppleScript` in HelmRuntime, which is where the escaping went: it was
    /// written out here and again in Homebrew's `OSAPrivilegedRunner`, under a
    /// comment calling that duplication deliberate «until there is a shared
    /// privileged runner to put them in». Of everything in this app written
    /// twice, this was the pair standing between a command root runs and a
    /// command somebody appends to.
    private static func privilegedScript(_ command: String) -> String {
        AppleScript.administratorShellScript(command)
    }

    /// Single quotes, with the one character that can end them turned into a
    /// close-escape-reopen. `AccountName.isPlausible` already refuses a name
    /// with a quote in it; this is what makes that a second line of defence
    /// rather than the only one.
    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
