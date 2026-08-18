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
///
/// `AppleScript`'s own doc comment predicted this file: the escaping moved to
/// `HelmRuntime` first «until there is a shared privileged runner to put them
/// in», and a second module needing the runner is what makes it worth having.
/// Homebrew's `OSAPrivilegedRunner` adopting it is a separate change.
public enum PrivilegedRun {

    /// AppleScript's number for a cancelled dialog. The *wording* is localized
    /// and cannot be matched on; the number is not.
    private static let userCancelled = "-128"

    /// Ask root to run `command`, through the system's own dialog.
    ///
    /// Blocking — `osascript` sits there for as long as the dialog is up, which
    /// can be minutes. Callers hop through `offTheCooperativePool` first, or a
    /// pool thread is parked for the length of somebody's coffee break.
    public static func run(_ command: String) -> PrivilegedOutcome {
        let result = HelmProcess.run("/usr/bin/osascript", arguments(for: command))
        return outcome(status: result.status, output: result.output)
    }

    /// What `run` hands the tool — a seam, so `-s o` below has a test under it
    /// that costs nobody a password dialog.
    ///
    /// **`-s o` is what makes `.declined` reachable at all.** `osascript(1)`:
    /// «e  Print script errors to stderr (default). / o  Print script errors to
    /// stdout.» — and `HelmProcess.run` sends the child's stderr to
    /// `FileHandle.nullDevice` deliberately, because a tool's diagnostics are
    /// not its output. Here the diagnostic *is* the output: `-128` is the only
    /// reliable sign of a cancelled dialog, since the wording beside it is in
    /// whatever language the person runs their Mac in. Without this flag the
    /// number is written to a stream nobody reads, `outcome` sees status 1 with
    /// an empty string, and every cancel is reported as a failed write — a
    /// three-way reading resting on something that is not there.
    ///
    /// The escaping stays in `AppleScript`: one place in this app decides
    /// whether root runs a command or an attacker's continuation of it.
    static func arguments(for command: String) -> [String] {
        ["-s", "o", "-e", AppleScript.administratorShellScript(command)]
    }

    /// Split out so the reading is testable without a password dialog.
    public static func outcome(status: Int32, output: String) -> PrivilegedOutcome {
        guard status != 0 else { return .done }
        if output.contains(userCancelled) { return .declined }
        return .failed(status)
    }
}
