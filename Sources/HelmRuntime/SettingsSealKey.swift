import Foundation

/// The key every setting Helm seals in its **own** namespace is checked against.
///
/// **One cache, not one per reader.** One keychain item is behind this
/// (`com.helm.app` / `settings-seal`), read by `AppSettings.scanGuard` and
/// `DuplicatesSettings.guardOfScanSettings`. A cache serialises only the
/// callers that share it, so two caches would mean two round trips, and on an
/// ad-hoc build a second modal dialog for anyone who answered "Allow" rather
/// than "Always Allow". Here because both readers' targets import this one.
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
    /// is an error anywhere. `TheRulesTheCompilerCannotHoldTests` holds that no other file spells them.
    public static let overScanSettings: SealKeyPort = overKeychain(forBundle: Bundle.main.bundleIdentifier)

    /// The cache over the item `identifier`'s build seals under. Building it reads nothing
    /// from the keychain; the first `key()` does.
    static func overKeychain(forBundle identifier: String?) -> SealKeyPort {
        SealKeyCache(KeychainSealKey(service: SettingsSealItems.service,
                                     account: SettingsSealItems.of(bundle: identifier).account,
                                     category: "scan"))
    }
}

/// Which keychain account the scan settings are sealed under.
///
/// **Helm Dev has an account of its own**, because Dev shares the person's
/// installed Helm's keychain and its saves would otherwise write seals under
/// the key the installed Helm reads. Exactly `AppBuild.devIdentifier` moves to
/// `dev-settings-seal`; anything else, a nil identifier included, reads the
/// deployed `settings-seal`. The service stays `com.helm.app`; the deployed
/// item is never re-keyed. A seal Dev wrote before this account existed is
/// signed with the shared key, so Dev reads it as a broken seal and refuses safe;
/// `defaults delete com.helm.app.dev` once starts Dev clean.
struct SettingsSealItems: Equatable, Sendable {
    /// Deployed: names the item on every Mac that has run a background scan.
    static let service = "com.helm.app"
    let account: String

    static func of(bundle identifier: String?) -> SettingsSealItems {
        SettingsSealItems(account: AppBuild.isDevIdentifier(identifier) ? "dev-settings-seal" : "settings-seal")
    }
}
