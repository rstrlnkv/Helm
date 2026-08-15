import Foundation
import HelmRuntime
import HelmTestSupport

/// The guard an engine built in this target is handed, in place of the one it
/// defaults to.
///
/// `DuplicatesEngine.init`'s `settings:` defaults to
/// `DuplicatesSettings.guardOfScanSettings`, which is `com.helm.app /
/// settings-seal` in the **person's** login keychain. Eight constructions here
/// took that default. None of them asks the guard anything today — `find` and
/// `trash` never reach `storedKeepPolicy()` — so nothing was written; what they
/// were was one refactor away from writing, with no way for the suite to notice,
/// which is what `ATestNamesTheKeychainPortsItBuildsOverTests` exists to stop.
///
/// `SealKeyProbe` rather than a fourth hand-rolled port: it is
/// `HelmTestSupport`'s, it spends first use exactly once the way
/// `KeychainSealKey` does, and it records the thread it was asked on. A test that
/// wants a keychain which will not answer asks for `SilentSealKey` instead —
/// those are two ports, not a flag on one, because no keychain turns into the
/// other mid-run.
func suiteSealGuard() -> SettingGuard { SettingGuard(keys: SealKeyProbe()) }
