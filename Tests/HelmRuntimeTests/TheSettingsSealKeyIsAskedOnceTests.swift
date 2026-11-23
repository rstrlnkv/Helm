import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// One keychain item, one cache over it.
///
/// `SealKeyCache` serialises the callers that share the instance and nobody
/// else, so two instances over one item are two `SecItemCopyMatching` calls —
/// and on an ad-hoc signed build, where the item's access list names a build
/// that no longer exists, the second is a second modal dialog for anyone who
/// answers the first with "Allow" rather than "Always Allow". That is what
/// shipped: `AppSettings.scanGuard` and `DuplicatesSettings.guardOfScanSettings`
/// each built one, each documenting at length that the item was shared.
///
/// That the item's names are spelled in one file only is held by
/// `TheRulesTheCompilerCannotHoldTests`; what is left here is the account mapping.
final class TheSettingsSealKeyIsAskedOnceTests: XCTestCase {

    /// The deployed account is what everything but Helm Dev reads; Dev has an
    /// account of its own so its saves never touch the installed Helm's item.
    func testOnlyHelmDevSealsUnderAnAccountOfItsOwn() {
        for identifier in [Optional("com.helm.app"), nil, "com.apple.dt.xctest.tool"] {
            XCTAssertEqual(SettingsSealItems.of(bundle: identifier).account, "settings-seal")
        }
        XCTAssertEqual(SettingsSealItems.of(bundle: "com.helm.app.dev").account, "dev-settings-seal")
        XCTAssertEqual(SettingsSealItems.service, "com.helm.app")
    }

    /// The wiring, not the mapping: the key the app builds addresses the account
    /// of its own build. A constant there would let Helm Dev write the installed
    /// Helm's seal item. Read from the built key; nothing is asked of the keychain.
    func testTheKeyIsBuiltOverTheAccountOfItsOwnBuild() throws {
        for (identifier, account) in [("com.helm.app.dev", "dev-settings-seal"), ("com.helm.app", "settings-seal")] {
            let cache = try XCTUnwrap(SettingsSealKey.overKeychain(forBundle: identifier) as? SealKeyCache)
            let keychain = try XCTUnwrap(cache.source as? KeychainSealKey)
            XCTAssertEqual(keychain.account, account, "the key built for \(identifier)")
        }
    }
}
