import Foundation
import HelmRuntime
import Security
import XCTest

/// **In a test process the production keychain port answers «unavailable» and
/// touches nothing.**
///
/// `ATestNamesTheKeychainPortsItBuildsOverTests` holds every construction a test
/// spells; `ModuleHost.bootstrap` builds engines no test spells, on their
/// production ports. Measured 2026-09-17: once this Mac's builds carried a
/// stable signing identity, the seal item's access list no longer matched the
/// test runner, Autopilot's key read waited on a dialog, and
/// `ShutdownLetsTheEnginesGoTests` found the engine still alive.
///
/// Asked of an account nothing else uses, so the defect — a port that does go
/// to the keychain — creates an item this test can see and then removes.
final class ATestRunNeverReachesTheLoginKeychainTests: XCTestCase {

    private let service = "com.helm.test"
    private let account = "a-test-run-never-reaches-the-login-keychain"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    override func tearDown() {
        SecItemDelete(query as CFDictionary)
        super.tearDown()
    }

    func testTheSealKeyPortAnswersUnavailableAndCreatesNothing() {
        XCTAssertTrue(TestProcess.isRunning, "this process does not know it is a test run")

        let key = KeychainSealKey(service: service, account: account, category: "test").key()
        XCTAssertNil(key, "the production seal-key port handed a test run a key")

        var request = query
        request[kSecReturnAttributes as String] = true
        XCTAssertEqual(SecItemCopyMatching(request as CFDictionary, nil), errSecItemNotFound, """
            the production seal-key port created an item in the login keychain of the machine \
            running the suite
            """)
    }
}
