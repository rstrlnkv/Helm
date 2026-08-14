import HelmRuntime
import XCTest
@testable import HelmApp

/// A keychain that can be in the state the real one starts in.
///
/// `TestKey` in `DisabledScansMustBeHelmsOwnTests` answers with a fixed
/// `firstUse` for ever, which is a fake simpler than its port: `KeychainSealKey`
/// **spends** first use — the run that creates the item gets `true` and every
/// later read gets `false`. So "the key was created by an earlier read, and the
/// door is shut" was a state no test could write down, which is exactly where
/// the defect lived.
private final class FakeKeychain: SealKeyPort, @unchecked Sendable {
    /// Only ever touched from the test's own main actor; `@unchecked` rather
    /// than a lock, so the fake's behaviour stays readable.
    private(set) var reads = 0
    private var material: Data?

    func key() -> SealKey? {
        reads += 1
        if let material { return SealKey(material: material, firstUse: false) }
        let made = Data(repeating: 0x5A, count: 32)
        material = made
        return SealKey(material: made, firstUse: true)
    }
}

/// The one door the seal leaves open, and who walks through it.
///
/// `SettingSeal.verdict` adopts an unsealed value when `key.firstUse` is true,
/// which is true only on the run that creates the keychain item. Nothing in the
/// app ever wrote `disabledScans`, and its getter returned the default *before*
/// touching the guard — so on every Mac the item was never created, first use
/// was still unspent, and the first value the app ever saw was adopted and
/// sealed as Helm's own. `defaults write com.helm.app disabledScans -array` is
/// the whole attack: a full-volume walk under Helm's Full Disk Access, blessed.
@MainActor
final class TheFirstReadClosesTheSealsDoorTests: XCTestCase {

    private let key = "disabledScans"
    private var macKey: String { SettingGuard.macKey(for: key) }
    private var savedValue: Any?
    private var savedMac: Any?
    private var savedGuard: SettingGuard!

    override func setUp() async throws {
        savedValue = AppSettings.store.object(key)
        savedMac = AppSettings.store.object(macKey)
        savedGuard = AppSettings.scanGuard
    }

    override func tearDown() async throws {
        AppSettings.store.set(savedValue, for: key)
        AppSettings.store.set(savedMac, for: macKey)
        AppSettings.scanGuard = savedGuard
    }

    /// A Mac nobody has configured: no stored value, no MAC, no keychain item.
    private func freshMac() -> FakeKeychain {
        AppSettings.store.set(nil, for: key)
        AppSettings.store.set(nil, for: macKey)
        let keychain = FakeKeychain()
        AppSettings.scanGuard = SettingGuard(keys: keychain)
        return keychain
    }

    func testReadingTheDefaultCreatesThisInstallationsKey() {
        let keychain = freshMac()
        XCTAssertEqual(AppSettings.disabledScans, ["disk"], "the default is still the default")
        XCTAssertGreaterThan(keychain.reads, 0,
                             "the first read must create the key, or first use stays unspent")
    }

    /// The harm, end to end: Helm reads its own default on day one, something
    /// else writes the plist afterwards, and that value is not Helm's.
    func testAValueWrittenAfterHelmsFirstReadIsNotAdopted() {
        _ = freshMac()
        _ = AppSettings.disabledScans                      // day one, nothing stored

        AppSettings.store.set([String](), for: key)        // "scan everything", unsigned
        // Assert the subject happened: the plist really does hold that value now.
        XCTAssertEqual(AppSettings.store.object(key) as? [String], [])

        XCTAssertEqual(AppSettings.disabledScans, Set(ScanRunner.scannableModules),
                       "an unsealed value arriving after day one is refused, not adopted")
    }

    /// And the reverse is still true: a value Helm itself wrote reads back.
    func testWhatHelmWroteAfterThatFirstReadIsStillItsOwn() {
        _ = freshMac()
        _ = AppSettings.disabledScans
        AppSettings.disabledScans = ["disk", "duplicates"]
        XCTAssertEqual(AppSettings.disabledScans, ["disk", "duplicates"])
    }
}
