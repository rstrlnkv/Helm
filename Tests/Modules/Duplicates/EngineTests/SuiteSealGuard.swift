import Foundation
import HelmRuntime
import HelmTestSupport

/// The guard an engine built in this target is handed, in place of the one it
/// defaults to.
///
/// `DuplicatesEngine.init`'s `settings:` defaults to
/// `DuplicatesSettings.guardOfScanSettings`, which is `com.helm.app /
/// settings-seal` in the **person's** login keychain. A construction that takes
/// the default is one refactor away from writing there
/// (`ATestNamesTheKeychainPortsItBuildsOverTests`).
///
/// `SealKeyProbe` spends first use exactly once the way `KeychainSealKey` does,
/// and records the thread it was asked on. A test that wants a keychain which
/// will not answer asks for `SilentSealKey` instead — two ports, not a flag on
/// one, because no keychain turns into the other mid-run.
func suiteSealGuard() -> SettingGuard { SettingGuard(keys: SealKeyProbe()) }
