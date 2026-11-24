import Foundation

/// What happened when root was asked.
///
/// **Three cases, because a `Bool` cannot hold the middle one.** A fake that
/// can only succeed or fail makes «the person pressed Cancel» a state no test
/// can write down, and that state is the *common* one: a password dialog is a
/// question, and people answer no.
public enum PrivilegedOutcome: Equatable, Sendable {
    case done
    case declined
    case failed(Int32)
}

/// The shared route to `do shell script … with administrator privileges`.
/// Homebrew's `OSAPrivilegedRunner` and KeepAwake's `PmsetClamshellPort` run
/// through it. Architecture/RunningOtherPrograms.md § Running other programs.
public enum PrivilegedRun {

    /// AppleScript's number for a cancelled dialog, in the shape `osascript`
    /// prints it. The *wording* is localized and cannot be matched on; the
    /// number is not.
    ///
    /// **The parentheses are load-bearing.** `do shell script` puts the failing
    /// command's own output inside the error it raises, so the text this match
    /// runs over is not all Helm's — a path like `/tmp/build-128/x` carries a
    /// bare `-128` through, and reading that as a cancel reports a failed write
    /// to root as a polite refusal. `(-128)` is the whole token, closing
    /// parenthesis included, so a longer number opening with the same digits is
    /// not it either.
    private static let userCancelled = "(-128)"

    /// Ask root to run `command`, through the system's own dialog.
    ///
    /// Blocking: `osascript` sits there for as long as the dialog is up, which
    /// can be minutes. Callers hop through `offTheCooperativePool` first.
    public static func run(_ command: String) -> PrivilegedOutcome {
        let result = HelmProcess.run("/usr/bin/osascript", arguments(for: command))
        return outcome(status: result.status, output: result.output)
    }

    /// What `run` hands the tool — a seam, so `-s o` below has a test under it
    /// that costs nobody a password dialog.
    ///
    /// **`-s o` is what makes `.declined` reachable at all.** `osascript(1)`:
    /// «o  Print script errors to stdout.» `HelmProcess.run` discards the
    /// child's stderr, because a tool's diagnostics are not its output; here the
    /// diagnostic *is* the output. Without the flag `outcome` sees status 1 with
    /// an empty string, and every cancel reads as a failed write. An ordinary
    /// script error takes the same route, so `outcome` tells them apart by
    /// number.
    ///
    /// The number, never the words: the sentence beside `(-128)` is in whatever
    /// language the person runs their Mac in.
    ///
    /// The escaping stays in `AppleScript`: one place in this app decides
    /// whether root runs a command or an attacker's continuation of it.
    static func arguments(for command: String) -> [String] {
        ["-s", "o", "-e", AppleScript.administratorShellScript(command)]
    }

    /// Split out so the reading is testable without a password dialog.
    static func outcome(status: Int32, output: String) -> PrivilegedOutcome {
        guard status != 0 else { return .done }
        if output.contains(userCancelled) { return .declined }
        return .failed(status)
    }
}
