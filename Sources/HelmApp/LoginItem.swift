import Foundation
import HelmRuntime
import ServiceManagement
import HelmAppStrings
import HelmUI

/// What «Open Helm at login» is actually doing, as against what it says.
///
/// **The switch needs a channel back from the only thing that can refuse it.**
/// `register()` can throw, and a person can remove Helm in System Settings
/// while the window is open, so the switch draws what macOS says and is
/// re-probed on every activation, like the permission rows below it.
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

    /// Whether switching off has a registration to give back. A registration
    /// waiting for approval is still a registration: leaving it makes the switch
    /// spring back on and Reset leave Helm in the login-item list.
    static func unregisters(from status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    /// The write itself, with the system's status and its two calls handed in so
    /// a test can watch which one `setEnabled` makes.
    static func request(_ on: Bool, status: SMAppService.Status,
                        register: () throws -> Void,
                        unregister: () throws -> Void) throws {
        if on {
            if status != .enabled { try register() }
        } else {
            if unregisters(from: status) { try unregister() }
        }
    }

    /// Ask, then report what the system says afterwards — never what was asked.
    @discardableResult
    static func setEnabled(_ on: Bool) -> LoginItemState {
        do {
            try request(on, status: SMAppService.mainApp.status,
                        register: { try SMAppService.mainApp.register() },
                        unregister: { try SMAppService.mainApp.unregister() })
        } catch {
            // Registration can fail for an unsigned or relocated build. That is
            // a fact about this Mac, and it reaches the screen.
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

extension AppStr {
    /// What the login switch has to say, and the two states where it says
    /// nothing: a caption under an ordinary switch is a caption nobody reads.
    ///
    /// Optional rather than an empty string, so the page cannot draw an empty
    /// `Text` — and so the compiler is what decides whether a new
    /// `LoginItemState` is spoken for.
    static func loginItemNote(_ state: LoginItemState,
                              language: AppLanguage = AppLanguage.current) -> String? {
        switch state {
        case .on, .off: return nil
        case .needsApproval: return loginItemNeedsApproval(language: language)
        case .refused: return loginItemRefused(language: language)
        }
    }
}
