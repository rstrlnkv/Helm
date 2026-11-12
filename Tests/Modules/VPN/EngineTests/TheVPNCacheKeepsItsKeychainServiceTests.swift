// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Security
import XCTest
@testable import Module_VPN_Engine

/// **The login-keychain items that cache a VPN's secrets are found by their
/// service string, and that string is already on people's machines.**
///
/// Any build that answered another service would read an empty cache and ask the
/// System keychain again (one prompt per VPN), and the one-time purge would miss
/// the old items. The function takes the bundle identifier so a build can later
/// answer differently; until then every identifier answers the deployed literal.
/// This touches no keychain: it asks a pure function.
final class TheVPNCacheKeepsItsKeychainServiceTests: XCTestCase {
    func testEveryBuildAnswersTheDeployedService() {
        for id in ["com.helm.app", nil, "com.apple.dt.xctest.tool"] {
            XCTAssertEqual(KeychainCredentials.service(for: id), "com.helm.vpn", "\(id ?? "nil")")
        }
    }

    /// The purge and the read/write both build their query through `cacheQuery`.
    func testTheQueriesCarryTheDeployedService() {
        XCTAssertEqual(KeychainCredentials.cacheQuery()[kSecAttrService as String] as? String, "com.helm.vpn")
        let one = KeychainCredentials.cacheQuery(account: "x.ss")
        XCTAssertEqual(one[kSecAttrService as String] as? String, "com.helm.vpn")
        XCTAssertEqual(one[kSecAttrAccount as String] as? String, "x.ss")
    }

    /// The purge's delete sends the deployed service and no account.
    func testThePurgeDeletesTheDeployedService() {
        var sent: [String: Any] = [:]
        let status = KeychainCredentials.deleteEveryCacheItem { q in
            sent = q as? [String: Any] ?? [:]
            return errSecItemNotFound
        }
        XCTAssertEqual(status, errSecItemNotFound)
        XCTAssertEqual(sent[kSecAttrService as String] as? String, "com.helm.vpn")
        XCTAssertNil(sent[kSecAttrAccount as String])
    }
}
