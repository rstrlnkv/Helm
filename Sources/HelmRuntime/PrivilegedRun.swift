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
    /// That paragraph rested on the man page when it was written. It was run on
    /// this machine on 2026-08-17, and the man page holds — three invocations,
    /// each reported as exit status, stdout, stderr:
    ///
    /// - `osascript -e 'error number -128'` → 1, stdout **empty**, stderr
    ///   `0:17: execution error: Отменено пользователем. (-128)`
    /// - `osascript -s o -e 'error number -128'` → 1, stdout
    ///   `0:17: execution error: Отменено пользователем. (-128)`, stderr empty
    /// - `osascript -s o -e 'error number -1728'` → 1, stdout
    ///   `0:18: execution error: Не удается получить «script». (-1728)`, stderr
    ///   empty
    ///
    /// Row 1 is the defect the flag exists to close: the only sign of a cancel
    /// went to the stream `HelmProcess` discards. Row 3 shows an ordinary script
    /// error takes the same route, so `outcome` reads one stream for both and
    /// tells them apart by number.
    ///
    /// And the message came back **in Russian** — not because the flag does
    /// that, but because this Mac runs in Russian. That is the independent
    /// proof that matching the number rather than the words was right: nothing
    /// in the sentence beside `(-128)` is the same on the next person's Mac.
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
