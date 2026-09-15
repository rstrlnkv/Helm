import Foundation

/// Everything the Homebrew module's engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an arm
/// is a build error rather than a command that silently answers nothing. A
/// string this enum cannot parse is a command the engine does not know, refused
/// once at the door instead of falling through a `default` nobody re-reads.
public enum HomebrewCommand: String, CaseIterable, Sendable {
    case status
    case listInstalled
    case outdated
    case descriptions
    case search
    /// Which installed packages still need a given one — asked once, at the
    /// moment the uninstall is put to the person, and never cached: the answer
    /// is about a Cellar that changes under the app.
    case dependents
    /// What `brew info --json=v2` knows about one package — asked once, when
    /// the person opens its detail, and never cached: the answer is about a
    /// Cellar and a catalogue that both change under the app.
    case info
    /// What `brew doctor` found, parsed from the diagnostics stream it prints
    /// its whole answer on — see `HomebrewEngine.doctor()` and
    /// `ProcessRunner.runCapturingDiagnostics`.
    case doctor
    /// Run one of the commands `brew doctor`'s answer was read as proposing.
    ///
    /// The payload is the argv itself — `["uninstall", "periphery"]` — and the
    /// engine **judges it again** before running it, against the installed list
    /// it reads at that moment. The UI's own judgement decides what to draw and
    /// nothing else: between the draw and the press a terminal can uninstall
    /// the very package the button names, and the argv the page carries is a
    /// reading of a Cellar that has moved (`HomebrewEngine.runDoctorFix`).
    case doctorFix
    case install
    case uninstall
    case upgrade
    case upgradeAll
    case installBrew
    /// End the running long operation, if any. The only way out of a brew that
    /// will not finish — operations have no deadline, because an install may
    /// honestly take an hour.
    case stop
}

/// Everything the module's engine says while a long operation runs.
///
/// **A name that crosses a target boundary is a constant both sides read.** The
/// engine spelled `"opLog"` and `"opState"` into `EngineEvent`, and the view
/// model spelled them again in the `switch` that receives them — the same
/// literal typed twice, which is an error nowhere. Rename one and the console
/// simply stops filling: the events keep arriving, the `switch` keeps not
/// matching, and nothing anywhere says so. The engine and the UI target both
/// import this file, so there is no reason for two spellings.
public enum HomebrewEvent: String, Sendable {
    /// One line of the tool's output, as it arrives.
    case opLog
    /// Where the operation is now: running, done or failed.
    case opState
}
