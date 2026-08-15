import Foundation
import HelmRuntime

/// Where the duplicate finder's own sealed settings get their key.
///
/// One item for everything Helm seals in its own namespace, and deliberately
/// **not** Autopilot's: that one is deployed on every Mac that has run the
/// module, and moving it would read there as "somebody rewrote your rules".
///
/// It lives in the engine target because the reader is the engine — the UI
/// writes through the same value, and a seal written by one and checked by the
/// other has to come from one place or it is two keys with one name.
/// **One guard over every scan setting this module stores, not one per
/// setting.** It was `guardOfFolder` while the folder was the only sealed value
/// here; the keep policy is the second, and a second `SettingGuard` beside it
/// would be a second keychain item for one question — while the item itself,
/// its account and its category are stored data on every Mac that has run a
/// background scan and never move. `TheScanSettingsSealDoesNotMoveTests`
/// records the three strings that address it.
public enum DuplicatesSettings {
    public static let guardOfScanSettings = SettingGuard(
        keys: KeychainSealKey(service: "com.helm.app", account: "settings-seal",
                              category: "scan"))

    /// Where the keep policy is stored, in the module's own namespace.
    ///
    /// One spelling for a name two targets use: the settings page writes it and
    /// the engine reads it, and a key only one side changes is an error nowhere
    /// — the reader simply gets the default for ever.
    public static let keepPolicyKey = "keepPolicy"
}
