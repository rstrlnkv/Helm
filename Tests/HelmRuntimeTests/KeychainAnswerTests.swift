import Security
import XCTest
@testable import HelmRuntime

/// What a keychain status becomes. `absent` makes the seal create a key and
/// gives Autopilot's mark nothing to check a rollback against, so it is
/// `errSecItemNotFound` alone; every other thing a keychain says is `refused`.
final class KeychainAnswerTests: XCTestCase {

    func testNotFoundIsTheOnlyAbsent() {
        XCTAssertEqual(KeychainItem.answer(status: errSecItemNotFound, item: nil), .absent)
    }

    func testAKeychainThatWillNotAnswerIsRefusedNeverAbsent() {
        for status in [errSecAuthFailed, errSecInteractionNotAllowed] {
            XCTAssertEqual(KeychainItem.answer(status: status, item: nil), .refused(status))
        }
    }

    func testSuccessWithDataIsFound() {
        let data = Data([1, 2, 3])
        XCTAssertEqual(KeychainItem.answer(status: errSecSuccess, item: data as CFData), .found(data))
    }

    func testSuccessWithNothingReadableIsRefusedNeverAbsent() {
        XCTAssertEqual(KeychainItem.answer(status: errSecSuccess, item: nil), .refused(errSecSuccess))
        XCTAssertEqual(KeychainItem.answer(status: errSecSuccess, item: "text" as CFString),
                       .refused(errSecSuccess))
    }

    func testOnlyAThirtyTwoByteKeyIsTaken() {
        for count in [0, 31, 33] {
            XCTAssertNil(KeychainSealKey.existing(Data(count: count)), "\(count) bytes")
        }
        let material = Data(repeating: 7, count: 32)
        XCTAssertEqual(KeychainSealKey.existing(material), SealKey(material: material, firstUse: false))
    }

    func testAddressIsTheGenericPasswordItemOfThatServiceAndAccount() {
        for (service, account) in [("com.helm.app", "settings-seal"),
                                   ("com.helm.autopilot", "rule-seal"),
                                   ("com.helm.autopilot", "rule-seq")] {
            let address = KeychainItem.address(service: service, account: account)
            XCTAssertEqual(address.count, 3)
            XCTAssertEqual(address[kSecClass as String] as? String, kSecClassGenericPassword as String)
            XCTAssertEqual(address[kSecAttrService as String] as? String, service)
            XCTAssertEqual(address[kSecAttrAccount as String] as? String, account)
        }
    }
}
