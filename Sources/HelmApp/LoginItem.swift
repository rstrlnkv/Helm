import Foundation
import HelmRuntime
import ServiceManagement

/// What «Open Helm at login» is actually doing, as against what it says.
///
/// **The switch had no channel back from the only thing that can refuse it.**
/// `setEnabled` caught `register()`'s throw and discarded it under a comment
/// about unsigned dev builds, and the page read the value once at construction
/// — so a refused registration left the switch on with Helm not opening at
/// login, and a person who removed Helm from System Settings while the window
/// was open saw a switch that still said yes. The permission rows sitting two
/// lines below it re-probe on every activation.
///
/// One value rather than a `Bool` beside a `Bool`, for the reason `TrashWatch`
/// gives: «asked for, and macOS refused» and «not asked for» are different
/// sentences, and a struct of flags is an invitation to write down the pair that
/// cannot happen.
enum LoginItemState: Equatable {
    /// Nobody asked, or the registration was taken away.
    case off
    /// Registered, and macOS says so.
    case on
    /// Registered, and waiting for the person to allow it in System Settings.
    case needsApproval
    /// The write threw. The switch does **not** stay on for this.
    case refused

    /// What the switch draws. `refused` is off, because that is what the Mac
    /// will do at the next login.
    var isOn: Bool { self == .on || self == .needsApproval }

    /// The state from the system's own answer and Helm's last attempt.
    ///
    /// The system outranks the memory: a refusal followed by an enabled
    /// registration — the person allowed it themselves — is history, and
    /// keeping it would be the same stale flag one layer up.
    static func state(status: SMAppService.Status, refused: Bool) -> LoginItemState {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return refused ? .refused : .off
        // Apple's enum, so an unknown case is a real possibility rather than a
        // build error. The safe reading of "macOS said something we do not
        // know" is not "Helm opens at login".
        @unknown default: return refused ? .refused : .off
        }
    }
}

/// Wraps the modern login-item API so Helm can start at login.
enum LoginItem {

    /// What macOS says right now. Asked again on every activation, not once.
    static func current(refused: Bool = false) -> LoginItemState {
        LoginItemState.state(status: SMAppService.mainApp.status, refused: refused)
    }

    /// Ask, then report what the system says afterwards — never what was asked.
    @discardableResult
    static func setEnabled(_ on: Bool) -> LoginItemState {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            // Registration can fail for an unsigned or relocated build. That is
            // a fact about this Mac and it now reaches the screen, rather than
            // being swallowed here and contradicted by a switch.
            HelmLog.shared.failure("login", on ? "could not register" : "could not unregister",
                                   error)
            return current(refused: true)
        }
        return current()
    }

    /// The door for `needsApproval`, which is otherwise a sentence pointing at a
    /// switch in the far corner.
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
