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
/// the old items. The function takes the bundle identifier: Helm Dev
/// answers `com.helm.vpn.dev` and every other identifier the deployed literal.
/// This touches no keychain: it asks a pure function.
final class TheVPNCacheKeepsItsKeychainServiceTests: XCTestCase {
    func testEveryNonDevBuildAnswersTheDeployedService() {
        for id in ["com.helm.app", nil, "com.apple.dt.xctest.tool"] {
            XCTAssertEqual(KeychainCredentials.service(for: id), "com.helm.vpn", "\(id ?? "nil")")
        }
    }

    /// Helm Dev's cache is its own service, a pinned literal.
    func testHelmDevKeepsItsOwnService() {
        XCTAssertEqual(KeychainCredentials.service(for: "com.helm.app.dev"), "com.helm.vpn.dev")
    }

    /// The purge and the read/write both build their query through `cacheQuery`.
    func testTheQueriesCarryTheDeployedService() {
        XCTAssertEqual(KeychainCredentials.cacheQuery()[kSecAttrService as String] as? String, "com.helm.vpn")
        let one = KeychainCredentials.cacheQuery(account: "x.ss")
        XCTAssertEqual(one[kSecAttrService as String] as? String, "com.helm.vpn")
        XCTAssertEqual(one[kSecAttrAccount as String] as? String, "x.ss")
    }

    /// Helm Dev's read, write and delete query carries its own service.
    func testHelmDevsQueriesCarryItsOwnService() {
        let q = KeychainCredentials.cacheQuery(account: "x.ss", bundleIdentifier: "com.helm.app.dev")
        XCTAssertEqual(q[kSecAttrService as String] as? String, "com.helm.vpn.dev")
        let real = KeychainCredentials.cacheQuery(bundleIdentifier: "com.helm.app")
        XCTAssertEqual(real[kSecAttrService as String] as? String, "com.helm.vpn")
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

    /// The purge itself, driven with a fake delete and a scratch marker: the
    /// real build sends exactly class generic password plus the deployed service
    /// and no account; Helm Dev sends nothing.
    func testThePurgeSendsTheExactQueryAndHelmDevSendsNothing() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("vpn-purge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        var sent: [[String: Any]] = []
        func purge(_ id: String?, marker: String) {
            KeychainCredentials.purgeTheCache(
                bundleIdentifier: id,
                marker: folder.appendingPathComponent(marker)) { q in
                sent.append(q as? [String: Any] ?? [:])
                return errSecSuccess
            }
        }

        purge("com.helm.app.dev", marker: "dev")
        XCTAssertTrue(sent.isEmpty, "Helm Dev must not delete the real Helm's items")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("dev").path),
                       "Helm Dev records no purge either")

        purge("com.helm.app", marker: "real")
        XCTAssertEqual(sent.count, 1)
        let query = try XCTUnwrap(sent.first)
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "com.helm.vpn")
        XCTAssertEqual(query.count, 2, "class and service, no account")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("real").path))
    }

    func testOnlyTheReleaseMayPurge() {
        XCTAssertFalse(KeychainCredentials.mayPurge(for: "com.helm.app.dev"))
        XCTAssertTrue(KeychainCredentials.mayPurge(for: "com.helm.app"))
    }
}
