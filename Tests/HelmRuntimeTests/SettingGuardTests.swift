import XCTest
@testable import HelmRuntime

private struct FixedKey: SealKeyPort {
    let material: Data
    let firstUse: Bool
    func key() -> SealKey? { SealKey(material: material, firstUse: firstUse) }
}

private struct NoKey: SealKeyPort {
    func key() -> SealKey? { nil }
}

/// A stored value that steers work nobody is watching has to be Helm's own.
///
/// `module.duplicates.folder` decides how far an unattended reader reaches and
/// `disabledScans` decides whether it reads at all. Both are plain values in
/// `com.helm.app.plist`, which any process running as this user can rewrite with
/// no permission of its own — the same shape Autopilot's rules had before they
/// were sealed, on a feature that walks the disk on a timer.
final class SettingGuardTests: XCTestCase {

    private let material = Data(repeating: 0x5A, count: 32)
    private let payload = Data("/Users/someone/Pictures".utf8)

    private func guarded(firstUse: Bool = false) -> SettingGuard {
        SettingGuard(keys: FixedKey(material: material, firstUse: firstUse))
    }

    func testAValueHelmSealedIsTrusted() {
        let sealed = guarded()
        let mac = sealed.seal(payload)
        XCTAssertNotNil(mac)
        XCTAssertEqual(sealed.verdict(payload: payload, mac: mac), .sealed)
    }

    /// The whole point: the payload changed and the MAC did not, because the
    /// writer of the plist does not have the key.
    func testAValueSomethingElseWroteIsRefused() {
        let sealed = guarded()
        let mac = sealed.seal(payload)
        XCTAssertEqual(sealed.verdict(payload: Data("/".utf8), mac: mac), .broken)
    }

    /// A MAC deleted along with the value it sealed is not a value that predates
    /// sealing — an attacker who can write the file can delete the seal too.
    /// Only the absence of the *key* says this installation never sealed.
    func testAMissingSealIsRefusedUnlessTheKeyIsNew() {
        XCTAssertEqual(guarded().verdict(payload: payload, mac: nil), .broken)
        XCTAssertEqual(guarded(firstUse: true).verdict(payload: payload, mac: nil), .adopt)
    }

    /// A locked keychain answers nothing, and nothing is not permission. This is
    /// the reachable case at login, before the person has typed anything.
    func testNoKeyMeansRefusal() {
        let sealed = SettingGuard(keys: NoKey())
        XCTAssertEqual(sealed.verdict(payload: payload, mac: "whatever"), .broken)
        XCTAssertNil(sealed.seal(payload))
    }

    /// Two different values under one key do not share a seal, which is what
    /// stops a MAC being copied from one setting to another in the same plist.
    func testASealIsSpecificToItsPayload() {
        let sealed = guarded()
        XCTAssertNotEqual(sealed.seal(payload), sealed.seal(Data("/Volumes".utf8)))
    }
}
