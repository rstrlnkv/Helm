import Foundation

/// The key every setting Helm seals in its **own** namespace is checked against.
///
/// **One cache, not one per reader.** There is one keychain item behind this —
/// `com.helm.app` / `settings-seal` — and it was already spelled out in both
/// places that read it: `AppSettings.scanGuard` and
/// `DuplicatesSettings.guardOfScanSettings` each built a `SealKeyCache` of their
/// own over it. A cache serialises the callers that share it and nobody else, so
/// two of them are two `SecItemCopyMatching` calls on one item — and on an
/// ad-hoc signed build, where the item's access list names a build that no
/// longer exists, the second is a second modal dialog in front of anyone who
/// answered the first with "Allow" rather than "Always Allow".
///
/// It lives here because the two readers are in different targets and this is
/// the one both already import; neither could hold it for the other.
///
/// Deliberately **not** Autopilot's item, which is sealed under
/// `com.helm.autopilot` / `rule-seal` on every Mac that has run that module —
/// moving those rules onto this key would read there as "somebody rewrote your
/// rules".
public enum SettingsSealKey {

    /// The three strings that address the item, and the cache in front of them.
    ///
    /// They are stored data on every Mac that has run a background scan: change
    /// one and the item is *absent*, which `KeychainSealKey` answers by creating
    /// a new one — so every setting the person really did save reads as
    /// tampered with, and Helm calls their own configuration a forgery. Nothing
    /// is an error anywhere. `TheSettingsSealKeyIsAskedOnceTests` records them.
    ///
    /// **The name was load-bearing and is not any more.**
    /// `ATestNamesTheKeychainPortsItBuildsOverTests` — the guard that stops a
    /// test writing into the developer's own login keychain — used to file the
    /// declarations it follows under the bare member name, and `Sources/` holds
    /// eight `static let shared`. Written as `shared`, this constant was
    /// shadowed by whichever singleton that walk read last; the chain from
    /// `DuplicatesSettings.guardOfScanSettings` down to `KeychainSealKey` went
    /// unrecognised and that guard went green over the very call sites it exists
    /// for. That is measured, not feared — it is how the first draft of this
    /// constant failed. The scan keys by the owning type now, so the collision
    /// is closed at its own end; the name is kept because it says what the
    /// constant is, not because anything depends on it.
    public static let overScanSettings: SealKeyPort =
        SealKeyCache(KeychainSealKey(service: "com.helm.app",
                                     account: "settings-seal",
                                     category: "scan"))
}
