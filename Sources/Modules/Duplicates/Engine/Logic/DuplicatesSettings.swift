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
public enum DuplicatesSettings {
    public static let guardOfFolder = SettingGuard(
        keys: KeychainSealKey(service: "com.helm.app", account: "settings-seal",
                              category: "scan"))
}
