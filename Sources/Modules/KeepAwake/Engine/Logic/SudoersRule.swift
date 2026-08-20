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

    /// What `sudo` is handed, word for word — and therefore what the rule has to
    /// spell, word for word, because `sudo` matches a command spec argument by
    /// argument. Written out twice (here as text for root, in `PmsetClamshellPort`
    /// as an argument vector) it is a name only one side ever changes, and the
    /// drift is not an error anywhere: it is a call that quietly starts asking
    /// for a password again.
    static func disableSleepArguments(on: Bool) -> [String] {
        [pmsetPath, "disablesleep", on ? "1" : "0"]
    }

    /// The rule's own withdrawal, for the same reason.
    static let removeArguments = ["/bin/rm", "-f", installedPath]

    /// The file, line by line. As narrow as it was — the two exact commands the
    /// module runs — plus the one that takes the file away again.
    ///
    /// **The withdrawal is what gives the grant a lifetime.** `sudoers` has no
    /// expiry and no conditionals, so until this line existed the only thing
    /// that could remove the rule was an administrator dialog, which needs
    /// somebody at the screen; dragging `Helm.app` to the Trash runs no code, so
    /// the grant stayed for the life of the machine naming an app that was gone.
    /// It is not a widening: the one thing it permits is deleting this very
    /// file, so the worst anything can do with it is take a privilege away.
    ///
    /// Two shapes deliberately not taken. Pointing the rule at a script *inside
    /// the bundle* would let deleting the app disarm the grant — and
    /// `/Applications` is writable by an admin without a password, so replacing
    /// that script buys permanent passwordless root: a leak turned into an
    /// escalation. A root-owned helper outside the bundle is not removed by
    /// dragging the app to the Trash either, so it answers nothing.
    ///
    /// The header is for whoever finds this file years from now with no Helm on
    /// the Mac. `#` opens a comment in sudoers **except** for `#include` and
    /// `#includedir` (and `@include`), which is why no header line's first word
    /// may be one of those — `TheRuleTakesItselfBackOutTests` is what keeps it
    /// that way. ASCII throughout: this is what root writes, and a character
    /// outside it is a question about `printf`, the shell's locale and `visudo`
    /// at once.
    static func lines(user: String) -> [String] {
        [
            "# Installed by Helm - Keep Awake, closed-lid option.",
            "# Lets this user run exactly the two pmset commands below without a password,",
            "# and lets Helm withdraw this file again without one.",
            "# Remove it by hand with:  sudo rm \(installedPath)",
            grant(user, [spec(disableSleepArguments(on: true)),
                         spec(disableSleepArguments(on: false))]),
            grant(user, [removeCommand()]),
        ]
    }

    /// One rule line: this account, root, no password, and nothing but these
    /// commands. Written out per line it was the same twelve characters of
    /// `ALL=(root) NOPASSWD:` twice, which is the part of this file that must
    /// not be retyped.
    private static func grant(_ user: String, _ commands: [String]) -> String {
        "\(user) ALL=(root) NOPASSWD: " + commands.joined(separator: ", ")
    }

    /// An argument vector as `sudo` spells it in a command spec.
    private static func spec(_ arguments: [String]) -> String {
        arguments.joined(separator: " ")
    }

    static func text(user: String) -> String { lines(user: user).joined(separator: "\n") }

    /// Write, lock down, check, move — and on any failure remove the staging
    /// file and report the failure. Without the `exit 1` a successful cleanup
    /// would be the command's exit status, and a refused rule would read as
    /// installed.
    ///
    /// One `printf` argument per line, never one argument with newlines in it:
    /// the whole command travels as a single AppleScript double-quoted literal,
    /// and a raw newline inside one of those is a syntax error rather than a
    /// newline.
    static func installCommand(user: String) -> String {
        let file = lines(user: user).map(shellQuoted).joined(separator: " ")
        return "/usr/bin/printf '%s\\n' \(file) > \(stagingPath)"
            + " && /bin/chmod 440 \(stagingPath)"
            + " && /usr/sbin/visudo -cf \(stagingPath)"
            + " && /bin/mv \(stagingPath) \(installedPath)"
            + " || { /bin/rm -f \(stagingPath); exit 1; }"
    }

    /// The withdrawal for the case the grant cannot cover it: a rule installed
    /// by a version of Helm from before the `rm` line existed, or one written by
    /// something else entirely. This is the one that costs a password.
    static func removeCommand() -> String { spec(removeArguments) }

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
