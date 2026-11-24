import Foundation

/// Building the one AppleScript Helm ever runs: a shell command handed to root
/// through the system's own password dialog.
///
/// **The escaping that matters most in the app, written once.** It is the
/// difference between a command root runs and a command an attacker appends
/// to: an unescaped `"` ends the literal and everything after it is
/// AppleScript, evaluated by a shell running as root. `PrivilegedRun` is the
/// runner. Architecture/RunningOtherPrograms.md § Running other programs.
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
