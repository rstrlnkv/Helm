import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// `guardOfFolder` became `guardOfScanSettings` when the keep policy joined the
/// folder under it, and a rename is exactly where stored data goes missing
/// quietly.
///
/// Three strings address the key every sealed value here is checked against, and
/// they are on every Mac that has run a background scan: change one and the
/// keychain item is *absent*, which `KeychainSealKey` answers by creating a new
/// one — so every setting the person really did save reads as tampered with, and
/// Helm calls their own configuration a forgery. Nothing is an error anywhere.
///
/// Read out of the source because there is nowhere else to read it: the guard
/// keeps its port private, and a test that asked the real keychain would write
/// to the person's own. `StoreNamespacesAreModuleIdsTests` records module ids
/// the same way and for the same reason.
final class TheScanSettingsSealDoesNotMoveTests: XCTestCase {

    private func settingsSource() throws -> String {
        try RepoSource.text(of: "Sources/Modules/Duplicates/Engine/Logic/DuplicatesSettings.swift")
    }

    func testTheKeychainItemIsTheOneThatShipped() throws {
        let source = try settingsSource()

        XCTAssertTrue(source.contains(#"service: "com.helm.app""#),
                      "the app's own namespace, deliberately not Autopilot's")
        XCTAssertTrue(source.contains(#"account: "settings-seal""#))
        XCTAssertTrue(source.contains(#"category: "scan""#),
                      "the log category names the feature that lost its key")
    }

    /// One guard, not one per setting: a second `SettingGuard` here would be a
    /// second keychain item for one question, and the item is the expensive part
    /// — on an ad-hoc signed build every one of them is a dialog
    /// (ARCHITECTURE.md § A seal needs a signature).
    func testThereIsExactlyOneGuardOverTheScanSettings() throws {
        let guards = try settingsSource().components(separatedBy: "\n")
            .map(RepoSource.code)
            .filter { $0.contains("SettingGuard(") }

        XCTAssertEqual(guards.count, 1, "found: \(guards)")
    }

    /// And the keychain is asked once for the whole process, not once per
    /// verdict.
    ///
    /// **Read out of the source for the same reason the strings above are**: the
    /// only behavioural way to ask whether this guard remembers its key is to
    /// warm it, which reaches the login keychain of whoever runs the suite. What
    /// the cache buys is measured through a port everywhere else
    /// (`TheKeepPolicyIsReadWhenItIsFreeTests`); this records that the module's
    /// own guard is the one that has it. Without it every read here is a
    /// `SecItemCopyMatching`, and on an ad-hoc build that is a modal
    /// authorization dialog — the engine pays one per background scan and the
    /// page paid one inside `init`, on the thread that draws.
    func testTheKeyIsFetchedOncePerProcess() throws {
        XCTAssertTrue(try settingsSource().contains("SealKeyCache(KeychainSealKey("), """
            the module's guard reaches the keychain directly, so every verdict is a round trip — \
            `AppSettings.scanGuard` is the shape this one follows
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
