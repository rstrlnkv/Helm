import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

private struct FixedKey: SealKeyPort {
    let material: Data
    let firstUse: Bool
    func key() -> SealKey? { SealKey(material: material, firstUse: firstUse) }
}

/// Every other setting in this module decides whether the Mac stays awake.
/// `clamshellEnabled` decides whether `sudo pmset disablesleep 1` runs — a
/// system-wide change, above every IOKit assertion, still in force after Helm
/// quits.
///
/// The administrator prompt needs a gesture behind it now, but *engaging* where
/// the grant already exists does not: any rule firing will do it. So a plist
/// edit is enough to make a Mac stop sleeping the next time a watched app is
/// launched — and `com.helm.app.plist` is a file any process running as this
/// user can rewrite with no permission of its own.
final class TheLidSettingIsHelmsOwnTests: XCTestCase {
    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private let key = Data(repeating: 7, count: 32)

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        settings = KeepAwakeSettings(store: store)
        KeepAwakeSettings.guardian = SettingGuard(keys: FixedKey(material: key, firstUse: false))
    }

    override func tearDown() {
        // Never the person's login keychain, and never left pointing at a test
        // key for whatever runs next.
        KeepAwakeSettings.guardian = SettingGuard(
            keys: KeychainSealKey(service: "com.helm.app", account: "keep-awake-seal",
                                  category: "clamshell"))
        super.tearDown()
    }

    private var storedMAC: String {
        store.string(SettingGuard.macKey(for: KeepAwakeSettings.Key.clamshellEnabled), default: "")
    }

    /// The control. Switched on through Helm, it reads back on — otherwise
    /// every refusal below is a feature that never worked.
    func testASettingHelmWroteReadsBack() {
        settings.setClamshellEnabled(true)
        XCTAssertTrue(settings.clamshellEnabled)
        XCTAssertFalse(storedMAC.isEmpty, "nothing was sealed, so nothing below is a seal test")
    }

    /// The forgery: `true` written straight into the plist, with no seal.
    func testAValueWrittenBehindHelmsBackIsRefused() {
        store.set(true, for: KeepAwakeSettings.Key.clamshellEnabled)

        XCTAssertFalse(settings.clamshellEnabled,
                       "a plist edit switched on the one setting that runs sudo, and the "
                       + "next rule to fire would have stopped this Mac sleeping")
    }

    /// …and a seal that belonged to a *different* value is not a seal for this
    /// one. Copying the MAC of `true` onto `false` and back is the cheapest
    /// forgery there is if the payload is only the value.
    func testASealFromAnotherValueDoesNotTransfer() {
        settings.setClamshellEnabled(false)
        let macForFalse = storedMAC
        store.set(true, for: KeepAwakeSettings.Key.clamshellEnabled)
        store.set(macForFalse,
                  for: SettingGuard.macKey(for: KeepAwakeSettings.Key.clamshellEnabled))

        XCTAssertFalse(settings.clamshellEnabled)
    }

    /// The migration, and the only door left open by it. An installation that
    /// has never sealed anything predates sealing: its stored value is taken
    /// once and sealed on the way out, so the lid does not silently stop
    /// working for somebody who had it switched on.
    func testAValueThatPredatesSealingIsAdoptedOnceAndThenSealed() {
        KeepAwakeSettings.guardian = SettingGuard(keys: FixedKey(material: key, firstUse: true))
        store.set(true, for: KeepAwakeSettings.Key.clamshellEnabled)

        XCTAssertTrue(settings.clamshellEnabled, "an existing user lost the feature on upgrade")
        XCTAssertFalse(storedMAC.isEmpty, "…and it was not sealed on the way out, so the "
                       + "next launch would adopt it again")

        // Sealed now: with the door shut, the same value still reads.
        KeepAwakeSettings.guardian = SettingGuard(keys: FixedKey(material: key, firstUse: false))
        XCTAssertTrue(settings.clamshellEnabled)
    }

    /// An unsealed `false` is not evidence of anything — «off» is what a
    /// missing seal falls back to anyway — so it costs no warning and no
    /// keychain read.
    func testAnUnsealedOffIsSimplyOff() {
        store.set(false, for: KeepAwakeSettings.Key.clamshellEnabled)
        XCTAssertFalse(settings.clamshellEnabled)
    }

    /// And the writer still writes. Refusing to save what a person asked for,
    /// because a reader might distrust it later, is the wrong end to fail at.
    func testSwitchingItOffIsStoredAndSealedToo() {
        settings.setClamshellEnabled(true)
        settings.setClamshellEnabled(false)

        XCTAssertFalse(settings.clamshellEnabled)
        XCTAssertFalse(storedMAC.isEmpty)
    }
}
