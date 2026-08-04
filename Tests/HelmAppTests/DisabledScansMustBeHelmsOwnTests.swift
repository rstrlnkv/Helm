import HelmRuntime
import XCTest
@testable import HelmApp

private struct TestKey: SealKeyPort {
    let firstUse: Bool
    func key() -> SealKey? {
        SealKey(material: Data(repeating: 0x77, count: 32), firstUse: firstUse)
    }
}

/// The switch that decides whether an unattended reader reads at all.
///
/// `disabledScans` is an off-list in `com.helm.app.plist`, and taking `disk` out
/// of it starts a walk of every filename on the volume with nobody at the desk —
/// on a machine whose owner may never have opened that module. Any process
/// running as this user can write that file with no permission of its own, which
/// is the same door Autopilot's rules were sealed against.
@MainActor
final class DisabledScansMustBeHelmsOwnTests: XCTestCase {

    private let key = "disabledScans"
    private var macKey: String { SettingGuard.macKey(for: key) }
    private var savedValue: Any?
    private var savedMac: String?
    private var savedGuard: SettingGuard!

    override func setUp() async throws {
        // The test process has its own defaults domain, and this puts back
        // whatever was in it either way: a harness leaves nothing behind.
        savedValue = AppSettings.store.object(key)
        savedMac = AppSettings.store.object(macKey) as? String
        savedGuard = AppSettings.scanGuard
    }

    override func tearDown() async throws {
        AppSettings.store.set(savedValue, for: key)
        AppSettings.store.set(savedMac, for: macKey)
        AppSettings.scanGuard = savedGuard
    }

    private func use(firstUse: Bool = false) {
        AppSettings.scanGuard = SettingGuard(keys: TestKey(firstUse: firstUse))
    }

    func testAListHelmWroteIsUsed() {
        use()
        AppSettings.disabledScans = ["disk"]
        XCTAssertEqual(AppSettings.disabledScans, ["disk"])
    }

    /// The attack in one line: somebody rewrites the plist to enable every scan.
    /// The answer is not "believe the file" and not "believe the default" — it
    /// is to run nothing until a person sets it again.
    func testAListSomethingElseWroteTurnsEveryScanOff() {
        use()
        AppSettings.disabledScans = ["disk"]
        AppSettings.store.set([String](), for: key)   // "scan everything", unsigned
        XCTAssertEqual(AppSettings.disabledScans, Set(ScanRunner.scannableModules))
    }

    /// And the seal cannot simply be deleted along with the value it protects.
    func testAListWithNoSealTurnsEveryScanOff() {
        use()
        AppSettings.store.set(["duplicates"], for: key)
        AppSettings.store.set("", for: macKey)
        XCTAssertEqual(AppSettings.disabledScans, Set(ScanRunner.scannableModules))
    }

    /// Except on the run that creates the key, where there is nothing else the
    /// value could be: it is adopted, and sealed on the way past.
    func testAListFromBeforeSealingIsAdoptedAndSealed() {
        use(firstUse: true)
        AppSettings.store.set(["disk"], for: key)
        AppSettings.store.set("", for: macKey)
        XCTAssertEqual(AppSettings.disabledScans, ["disk"])
        XCTAssertFalse(AppSettings.store.string(macKey, default: "").isEmpty)
    }
}
