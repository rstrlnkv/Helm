import Foundation

/// Building the one AppleScript Helm ever runs: a shell command handed to root
/// through the system's own password dialog.
///
/// **Two modules wrote this escaping out, and it is the escaping that matters
/// most in the app.** `SudoersRule.appleScriptLiteral` carried it with a comment
/// saying Homebrew's `OSAPrivilegedRunner.runAdmin` had the same two lines,
/// «deliberate duplication, until there is a shared privileged runner to put
/// them in». This is that place. What sits behind the two copies is the
/// difference between a command root runs and a command an attacker appends to:
/// an unescaped `"` ends the literal and everything after it is AppleScript,
/// evaluated by a shell running as root.
///
/// A shared *runner* is the larger idea and still worth having — Homebrew's
/// port spawns `osascript` itself and so does `PmsetClamshellPort`. The escaping
/// is the half that must not be written twice, so it moves first.
public enum AppleScript {

    /// A string as an AppleScript double-quoted literal's contents.
    ///
    /// Backslash first, then the quote — the other order would escape the
    /// backslash this call had just introduced.
    public static func literal(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// `do shell script "…" with administrator privileges` — the system dialog
    /// where the person types their own password, never a password Helm holds.
    public static func administratorShellScript(_ command: String) -> String {
        "do shell script \"\(literal(command))\" with administrator privileges"
    }
}
