import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// The harness of every test of the sealed `disabledScans` setting: it saves the stored value, its MAC and the
/// app's seal guard before each test and puts them back after, so a test may overwrite all three.
///
/// A base with no tests of its own, as `KeepAwakeEngineRig` is: the classes keep their names, so
/// `Tests/optional-tests.txt` and `--filter` still match them.
@MainActor
class DisabledScansTestCase: XCTestCase {

    let key = "disabledScans"
    var macKey: String { SettingGuard.macKey(for: key) }
    private var savedValue: Any?
    private var savedMac: Any?
    private var savedGuard: SettingGuard!

    override func setUp() async throws {
        // The test process has its own defaults domain, and this puts back
        // whatever was in it either way: a harness leaves nothing behind.
        savedValue = AppSettings.store.object(key)
        savedMac = AppSettings.store.object(macKey)
        savedGuard = AppSettings.scanGuard
    }

    override func tearDown() async throws {
        AppSettings.store.set(savedValue, for: key)
        AppSettings.store.set(savedMac, for: macKey)
        AppSettings.scanGuard = savedGuard
    }

    /// A Mac nobody has configured: no stored value, no MAC, no keychain item. `cached` puts the probe behind a
    /// `SealKeyCache` as the app has it; `gate` holds the probe's read until the test lets it go.
    func freshMac(cached: Bool = false, gate: DispatchSemaphore? = nil) -> SealKeyProbe {
        AppSettings.store.set(nil, for: key)
        AppSettings.store.set(nil, for: macKey)
        let keychain = SealKeyProbe(gate: gate)
        AppSettings.scanGuard = SettingGuard(keys: cached ? SealKeyCache(keychain) : keychain)
        return keychain
    }
}
