import Foundation

/// Whether a launchd label is one Helm's switch will act on.
///
/// **One rule, read by the offer and by the port, because they had two.** The
/// label is not Helm's: it is whatever string a `.plist` in a LaunchAgents folder
/// put in its `Label` key, and `LaunchAgentReader` passes it through untouched.
/// `ActiveExtensions.setDisabled` refused a `/` before running anything while
/// `LeftoverActions.available` offered «Turn off» to any agent with a non-empty
/// label — so the page drew a live button, the press asked launchd nothing, and
/// the rescan afterwards drew the same row unchanged. The shape
/// `StaleItem.removable` already uses: the safer of two answers has to be the
/// only answer, and it cannot be if there are two of them.
///
/// Three characters stop a label being a label by the time it reaches launchd:
///
///   • **`/`** re-points the service target at the domain itself, and
///     `launchctl bootout gui/<uid>` ends the user's login session.
///   • **`"` and a newline** forge a line in `launchctl print-disabled`, whose
///     format is one `"label" => disabled` to a line with no escaping for
///     either — so a label carrying them prints as two lines that
///     `LaunchctlDisabled.parse` reads as two labels, and the second is a job
///     nobody switched off wearing this module's «Disabled» badge from then on.
///     Helm was the forger: nothing stopped it writing such a label itself.
///
/// The list is read back rather than parsed apart, so a line another program
/// forged cannot be told from a real one — refusing to write one is the whole of
/// the defence available here.
enum LaunchLabel {
    static func isSwitchable(_ label: String) -> Bool {
        // Empty is not a label either: launchd lets a job omit `Label` and take
        // its name from the file, and `gui/<uid>/` with nothing after it names
        // the domain rather than a service in it.
        !label.isEmpty
            && !label.contains("/")
            && !label.contains("\"")
            && !label.contains(where: \.isNewline)
    }
}
