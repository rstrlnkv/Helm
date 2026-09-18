import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// `guardOfFolder` became `guardOfScanSettings` when the keep policy joined the
/// folder under it, and a rename is exactly where stored data goes missing
/// quietly.
///
/// What is left here is what is this module's own. The three strings that address
/// the keychain item, and the single cache in front of it, moved to
/// `SettingsSealKey` with the item itself — `TheSettingsSealKeyIsAskedOnceTests`
/// records them, and records that nothing else addresses it.
///
/// Read out of the source because there is nowhere else to read it: the guard
/// keeps its port private, and a test that asked the real keychain would write
/// to the person's own. `StoreNamespacesAreModuleIdsTests` records module ids
/// the same way and for the same reason.
final class TheScanSettingsSealDoesNotMoveTests: XCTestCase {

    private func settingsSource() throws -> String {
        try RepoSource.text(of: "Sources/Modules/Duplicates/Engine/Logic/DuplicatesSettings.swift")
    }

    /// One guard, not one per setting: a second `SettingGuard` here would be a
    /// second keychain item for one question, and the item is the expensive part
    /// — on an ad-hoc signed build every one of them is a dialog
    /// (ARCHITECTURE.md § Sealed settings).
    func testThereIsExactlyOneGuardOverTheScanSettings() throws {
        let guards = try settingsSource().components(separatedBy: "\n")
            .map(RepoSource.code)
            .filter { $0.contains("SettingGuard(") }

        XCTAssertEqual(guards.count, 1, "found: \(guards)")
    }

    /// And it takes the shared key rather than reaching for the keychain itself:
    /// a cache built here would be a second one over an item that already has
    /// one, which is a second `SecItemCopyMatching` and — on an ad-hoc build —
    /// a second modal dialog.
    ///
    /// **Read out of the source for the same reason the rest is**: the only
    /// behavioural way to ask whether this guard remembers its key is to warm
    /// it, which reaches the login keychain of whoever runs the suite. What the
    /// cache buys is measured through a port elsewhere
    /// (`TheKeepPolicyIsReadWhenItIsFreeTests`).
    func testTheGuardTakesTheSharedKeyAndMakesNoneOfItsOwn() throws {
        let source = try settingsSource()

        XCTAssertTrue(source.contains("SettingsSealKey.overScanSettings"))
        XCTAssertFalse(source.contains("KeychainSealKey("), """
            the module reaches the keychain itself, so its reads are a round trip the app's \
            own guard has already paid for
            """)
    }

    /// The store keys are stored data too, and the MAC's spelling is derived
    /// from the value's rather than written twice. Recorded as the literals that
    /// shipped: deriving both sides here would be a test whose two halves read
    /// one constant, which cannot fail.
    func testTheStoredKeysAreTheOnesAlreadyOnPeoplesMacs() {
        XCTAssertEqual(DuplicatesSettings.keepPolicyKey, "keepPolicy")
        XCTAssertEqual(SettingGuard.macKey(for: "folder"), "folderMAC")
        XCTAssertEqual(SettingGuard.macKey(for: DuplicatesSettings.keepPolicyKey),
                       "keepPolicyMAC")
    }
}
