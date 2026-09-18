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
    /// **Not `shared`, and the name is load-bearing.**
    /// `ATestNamesTheKeychainPortsItBuildsOverTests` derives what reaches the
    /// keychain by following `static let` declarations, and files them in a
    /// dictionary keyed by the **bare** member name — so the eighth `shared` in
    /// the tree overwrites the seventh. Called `shared`, this constant is
    /// shadowed by whichever singleton that walk reads last; the chain from
    /// `DuplicatesSettings.guardOfScanSettings` down to `KeychainSealKey` then
    /// goes unrecognised, and every `settings:` default in the tree reads as
    /// harmless to the one guard that stops a test writing into somebody's own
    /// login keychain. Measured rather than feared: written as `shared`, this
    /// constant took that scan green over it, which is a guard dying quietly.
    public static let overScanSettings: SealKeyPort =
        SealKeyCache(KeychainSealKey(service: "com.helm.app",
                                     account: "settings-seal",
                                     category: "scan"))
}
