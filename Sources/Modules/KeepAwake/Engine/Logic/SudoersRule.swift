import Foundation
import HelmRuntime

/// The sudoers rule that lets Keep Awake run `pmset disablesleep`, and the
/// exact command root is asked to run to put it there.
///
/// Pure text, so the shape of what root does is a unit test. Root is handed
/// the content, never a user-writable path: a staged path stands in `ps auxww`
/// for as long as the password prompt is up, `visudo -cf` checks syntax and not
/// authorship, and any process running as this user could swap the file for
/// `<user> ALL=(ALL) NOPASSWD: ALL` and be handed permanent passwordless root.
public enum SudoersRule {
    /// Where sudo reads the rule from. `/etc/sudoers.d` is root-owned, so every
    /// file this command touches is one only root can write.
    ///
    /// `public` because the screen that asks for the password names it: the row
    /// says where the grant lands and the explanation behind it carries the
    /// `sudo rm` that takes it away by hand, so the path is spelled once.
    ///
    /// Helm Dev has a file of its own, so switching the lid option on and off
    /// there never creates, finds or withdraws the real Helm's grant.
    public static let installedPath = current.installed

    /// The two paths and the one argument vector that name the rule's file, all
    /// derived from the bundle identifier so a test drives them with the Dev id
    /// and the release id. The one `Bundle.main` read below is the only thing
    /// no test can pin.
    struct Paths: Equatable {
        let installed: String
        /// Written first under this name so sudo never reads a half-written or
        /// unchecked file: the move into place is a rename on the same filesystem.
        let staging: String
        /// The rule's own withdrawal, for the same reason.
        let removeArguments: [String]
    }

    static func paths(bundleIdentifier: String?) -> Paths {
        let installed = path(bundleIdentifier: bundleIdentifier)
        return Paths(installed: installed, staging: installed + ".new",
                     removeArguments: ["/bin/rm", "-f", installed])
    }

    static let current = paths(bundleIdentifier: Bundle.main.bundleIdentifier)

    /// `helm-keepawake-dev` for Helm Dev, `helm-keepawake` for everything else
    /// (the release, a test runner, a bundle that will not say what it is).
    /// No dot in either: `sudo` skips `includedir` files whose name has one.
    static func fileName(bundleIdentifier: String?) -> String {
        AppBuild.isDevIdentifier(bundleIdentifier) ? "helm-keepawake-dev" : "helm-keepawake"
    }

    static func path(bundleIdentifier: String?) -> String {
        "/etc/sudoers.d/" + fileName(bundleIdentifier: bundleIdentifier)
    }

    static let pmsetPath = "/usr/bin/pmset"

    /// What `sudo` is handed, word for word — and therefore what the rule has to
    /// spell, word for word, because `sudo` matches a command spec argument by
    /// argument. Spelled once for the rule and for `PmsetClamshellPort`'s
    /// argument vector: a drift between them is no error anywhere, only a call
    /// that quietly starts asking for a password again.
    static func disableSleepArguments(on: Bool) -> [String] {
        [pmsetPath, "disablesleep", on ? "1" : "0"]
    }

    static let removeArguments = current.removeArguments

    /// The file, line by line: the two exact commands the module runs, plus
    /// the one that takes the file away again.
    ///
    /// **The withdrawal is what gives the grant a lifetime.** `sudoers` has no
    /// expiry and no conditionals, and dragging `Helm.app` to the Trash runs no
    /// code, so without it only an administrator dialog could remove the rule.
    /// It is not a widening: the one thing it permits is deleting this very
    /// file, so the worst anything can do with it is take a privilege away.
    ///
    /// Not a script *inside the bundle*: `/Applications` is writable by an
    /// admin without a password, so replacing that script would buy permanent
    /// passwordless root. Not a root-owned helper outside the bundle either: the
    /// Trash does not remove it, so it answers nothing.
    ///
    /// The header is for whoever finds this file years from now with no Helm on
    /// the Mac. `#` opens a comment in sudoers **except** for `#include` and
    /// `#includedir` (and `@include`), which is why no header line's first word
    /// may be one of those — `TheRuleTakesItselfBackOutTests` is what keeps it
    /// that way. ASCII throughout: this is what root writes, and a character
    /// outside it is a question about `printf`, the shell's locale and `visudo`
    /// at once.
    static func lines(user: String, paths: Paths = current) -> [String] {
        [
            "# Installed by Helm - Keep Awake, closed-lid option.",
            "# Lets this user run exactly the two pmset commands below without a password,",
            "# and lets Helm withdraw this file again without one.",
            "# Remove it by hand with:  sudo rm \(paths.installed)",
            grant(user, [spec(disableSleepArguments(on: true)),
                         spec(disableSleepArguments(on: false))]),
            grant(user, [removeCommand(paths: paths)]),
        ]
    }

    /// One rule line: this account, root, no password, and nothing but these
    /// commands. `ALL=(root) NOPASSWD:` is the part of this file that must not
    /// be retyped.
    private static func grant(_ user: String, _ commands: [String]) -> String {
        "\(user) ALL=(root) NOPASSWD: " + commands.joined(separator: ", ")
    }

    /// An argument vector as `sudo` spells it in a command spec.
    private static func spec(_ arguments: [String]) -> String {
        arguments.joined(separator: " ")
    }

    static func text(user: String, paths: Paths = current) -> String {
        lines(user: user, paths: paths).joined(separator: "\n")
    }

    /// Write, lock down, check, move — and on any failure remove the staging
    /// file and report the failure. Without the `exit 1` a successful cleanup
    /// would be the command's exit status, and a refused rule would read as
    /// installed.
    ///
    /// One `printf` argument per line, never one argument with newlines in it:
    /// the whole command travels as a single AppleScript double-quoted literal,
    /// and a raw newline inside one of those is a syntax error rather than a
    /// newline.
    static func installCommand(user: String, paths: Paths = current) -> String {
        let (staging, installed) = (paths.staging, paths.installed)
        let file = lines(user: user, paths: paths).map(shellQuoted).joined(separator: " ")
        return "/usr/bin/printf '%s\\n' \(file) > \(staging)"
            + " && /bin/chmod 440 \(staging)"
            + " && /usr/sbin/visudo -cf \(staging)"
            + " && /bin/mv \(staging) \(installed)"
            + " || { /bin/rm -f \(staging); exit 1; }"
    }

    /// The withdrawal for a rule the grant cannot cover — one with no `rm`
    /// line of its own, or one written by something else entirely. This is the
    /// one that costs a password.
    static func removeCommand(paths: Paths = current) -> String { spec(paths.removeArguments) }

    /// Single quotes, with the one character that can end them turned into a
    /// close-escape-reopen. `AccountName.isPlausible` already refuses a name
    /// with a quote in it; this is what makes that a second line of defence
    /// rather than the only one.
    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
